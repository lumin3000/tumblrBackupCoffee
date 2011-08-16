request = require 'request'
xml2js = require 'xml2js'
mongoose = require 'mongoose'
mongodb = require 'mongodb'
fs = require 'fs'

#config
env = 'development' #production
tumblrDomain = "staff.tumblr.com"
Db = mongodb.Db
Collection = mongodb.Collection
GridStore = mongodb.GridStore
Chunk = mongodb.Chunk
Server = mongodb.Server

MONGODB = 'tumblr_bak_images_dev'
MONGODBclient = new Db(MONGODB, new Server("127.0.0.1", 27017, {auto_reconnect: true, poolSize: 4}))

mongoose.connect 'mongodb://localhost/tumblr_bak_dev'
Schema = mongoose.Schema
ObjectId = Schema.ObjectId

tumblrReadLimited = 50
readNumber = 0
proxy = null
writeLocalImageFile = false
v1_address = "http://#{tumblrDomain}/api/read?num=#{tumblrReadLimited}&start="
#proxy="http://127.0.0.1:3213"
#helper
log =  (str)-> console.log str if env == 'development'

timestamp2date = (str)->new Date(parseInt(str,10)*1000)

dategmt2month  = (str)->
  month = str.split('-')
  "#{month[0]}-#{month[1]}"

getImage1280 = (arr)->
  theImage=''
  arr.forEach (el)->
    if el['@']['max-width'] =='1280'
      theImage = el['#']
  theImage 

getPostTitle = (data)->
  return data['regular-title'] if data['regular-title']
  return data['link-text'] if data['link-text']
  return data['quote-text'] if data['quote-text']
  return data['photo-caption'] if data['photo-caption']
  return data['conversation-title'] if data['regular-title']
  return data['video-caption'] if data['video-caption']  
  return data['audio-caption'] if data['audio-caption']
  return data['question'] if data['question']
  return "notitle_ #{data['@']['type']}:  #{data['@']['url']}"
  
#model
monthlyPostsSchema = new Schema
  month:        {type:String, required: true}
  postsnumber:  Number

tumInfoSchema = new Schema
  domain:       {type:String, index:{unique:true},required: true}
  latestdate:   Date
  latestid:     String
  posts:        Number
  origin:       String
  monthlyPosts: [monthlyPostsSchema]
  
tumPostSchema = new Schema
  domain:       {type: String,  index:true}
  id:           {type:String, index:{unique:true},required: true}
  tag:          {type:[String],index:true}
  type:         String
  date:         Date
  month:        String
  image:        String
  url:          String
  title:        String
  origin:       String
  
imagesTaskSchema = new Schema
  title:        {type:String,default:'tumblr'}
  images:       [String]

#MonthlyPosts  = mongoose.model("MonthlyPosts", monthlyPostsSchema)
TumInfo       = mongoose.model("TumInfo", tumInfoSchema)
TumPost       = mongoose.model("TumPost", tumPostSchema)
ImagesTask    = mongoose.model("ImagesTask", imagesTaskSchema)

#logic

tumblog = {}
tumblog.posts = []
tumblog.pic1280 = []

writeXml = (str)->
  fs.open './tmp/xml.xml','a',666,(e,fsid)->
    fs.write fsid,str,null,'utf8', (e,fsid)->
      fs.close fsid, ()->
        log 'file writed'
        process.exit()
writeXml.str = ''
       
openImage = (filename)->
  GridStore.read MONGODBclient,filename, (err,filedata)=>
    fs.writeFile './tmp/'+filename.replace(/\//g,'|')+'.jpg',filedata,'binary',(err)->
      log "writeLocalImageFile ok~"

#https://github.com/christkv/node-mongodb-native/blob/master/docs/gridfs.md
saveImage = (filename,data,cb)->
  MONGODBclient.open ()=>
    gridStoreW = new GridStore(MONGODBclient, filename, "w")
    gridStoreW.open (err,gs)=>
      return log "#{gridStoreW.open}: #{err}" if err
      gs.write data, (err,gs)=>
        return log "#{gs.write}: #{err}" if err
        gs.close (err,result)=>
          return log "#{gs.close}: #{err}" if err
          MONGODBclient.close ()=>
            openImage filename if writeLocalImageFile
            cb()


parser = new xml2js.Parser()
parser.inited = false
parser.on 'end', (res)->
  if parser.inited == false
    parser.inited = true
    tumStore.main(res)
  else
    res2tumblog(res)

requestXmlTryagain = ()->
  if requestXmlTryagain.timeout < requestXmlTryagain.times
    requestXmlTryagain.timeout++
    log "request xml err, we try again, this is the #{requestXmlTryagain.timeout} try!!!"
    requestXml()
  else
    log "request timeout:#{requestXmlTryagain.times} times."
    process.exit()
requestXmlTryagain.timeout = 0
requestXmlTryagain.times = 3

requestXml = ()->
  options =
    uri:v1_address+readNumber
    proxy:proxy
    timeout:45000
  request options, (error, response, body)->
    if !error && response.statusCode == 200
      parser.parseString body
      writeXml.str+=body
      requestXmlTryagain.timeout = 0
    else
      requestXmlTryagain()
      #writeXml body, ()->parser.parseString body
    
requestImage = (addr,cb)->
  log "getting #{addr}............"
  addr = {uri:addr,proxy:proxy,encoding:'binary',timeout:45000}
  request addr, (error, response, body)->
    if !error && response.statusCode == 200
      log typeof body
      saveImage(addr.uri,body,cb) 
    else
      if error
        log "#{error};;!!!!!!!!!!!!!!!!!!!!get image error"
        #todo a timeout logic
        imagesTask.start()
      else
        log "#{response.statusCode};;!!!!!!!!!!!!!!!!!!!!get image error"
    #log "image#{body}"

imagesTask = 
  running:false
  task: {}
  prevDoc:""
  load:(cb)->
    @task = new ImagesTask {images:[]}
    
    ImagesTask.findOne (err,doc)=>
      if doc
        @task.images = doc.images
        @prevDoc = doc
      cb()
  update:(cb)->
    if @task.images.length<1
      return cb()
    if @prevDoc == ""
      @task.save (err)=>
        if err
          log "imagesTask.update::save() error: #{err}" 
        else 
          @prevDoc = {images:@task.images}
          cb()
      return
    else
      ImagesTask.update {title:"tumblr"},{images:@task.images},(err)=>
        if err
          return log "imagesTask.update::update() error: #{err}"
        else
          ImagesTask.findOne (err,doc)=>
          @prevDoc.images = @task.images
          cb()
  add:(arr,cb)->
    arr.forEach (el)=>
      @task.images.push(el) if @task.images.indexOf(el) < 0
    @update cb
  remove:(cb)->    
    @task.images.shift()
    if @task.images.length>0
      @update cb
    else
      ImagesTask.remove {title:"tumblr"},()=>
        log 'all task clean'
        cb()
  start:()->
    if @task.images.length>0
      requestImage @task.images[0], ()=>
        @remove ()=>
          @start()
    else
      log "no images in task - #{new Date()}"


tumStore = ()->    
  function_return =
    dbError:(str)->
      log "dbError___#{str}"
    postsCreated:0
    init:(res)->
      tumblog.info = res.tumblelog if !tumblog.info
      if !res.posts
        log "tumblr service maybe down , try again or use proxy" 
        process.exit()
      
      tumblog.postCount = parseInt(res.posts['@']['total'],10) if !tumblog.postCount
      tumblog.info = new TumInfo
        domain:       if tumblog.info['@']['cname'] then tumblog.info['@']['cname'] else "#{tumblog.info['@']['name']}.tumblr.com"
        latestdate:   timestamp2date res.posts.post[0]['@']['unix-timestamp']
        latestid:     res.posts.post[0]['@']['id']
        posts:        tumblog.postCount
        origin:       JSON.stringify tumblog.info
        monthlyPosts: []
      @monthlyPosts = []
    loadMonthlyPosts:(monthArray)->
        @monthlyPosts = monthArray
    updateMonthlyPosts:(month)->
      newMonth = true
      @monthlyPosts.forEach (el,idx)->
        if el['month'] == month
          el['postsnumber'] = el['postsnumber']++
          newMonth = false
      @monthlyPosts.push {month:month,postsnumber:1} if newMonth == true
    loadInfo:(cb)->
      TumInfo.findOne {domain:tumblog.info.domain},(err, doc)->
        return @dbError "loadInfo:#{err}" if err
        cb doc
    preSaveInfo:()->
      tumblog.info.monthlyPosts = @monthlyPosts
    createInfo:(cb)-> 
      @preSaveInfo()
      tumblog.info.save (err)=>if err then @dbError "createInfo:#{err}" else cb()
    updateInfo:(cb)-> 
      @preSaveInfo()
      TumInfo.remove {domain:tumblog.info.domain},()=>
        tumblog.info.save (err)=>if err then @dbError "updateInfo:#{err}" else cb()
    createPosts:(cb)->
      data = tumblog.posts[0]
      posts = new TumPost
        domain:       tumblog.info.domain
        id:           data['@']['id']
        tag:          if typeof data['tag']=='string' then [data['tag']] else (data['tag'] || null)
        type:         data['@']['type']
        date:         timestamp2date data['@']['unix-timestamp']
        month:        dategmt2month data['@']['date-gmt']
        image:        if data['photo-url'] then getImage1280(data['photo-url']) else null
        url:          data['url-with-slug']
        title:        getPostTitle data
        origin:       JSON.stringify data
      
      @updateMonthlyPosts posts.month
        
      posts.save (err)=>
        if err
          log posts.id
          @dbError "posts.save:#{err}" 
        else
          @postsCreated++
          tumblog.posts.shift()
          if tumblog.posts.length>0
            @createPosts(cb)
          else
            cb()
       
    updatePosts:(cb)->
      @createPosts cb
    main:(res)->
      @init res    
      @loadInfo (doc)=>
        if !doc # new blog
          tumblog.postsNumber = tumblog.info.posts
          @save = (cb)=>
            @createPosts ()=> 
              log "createPosts#{tumblog.postsNumber}"
              @createInfo ()=>  
                log "createInfo: done, total #{@postsCreated} posts added"
                cb()
        else #update if has new posts
          if doc.posts < tumblog.info.posts
            tumblog.postsNumber = tumblog.info.posts - doc.posts
            log "#{doc.posts} posts currently. #{tumblog.postsNumber} posts to add"
            @loadMonthlyPosts doc.monthlyPosts
            @save = (cb)=>
              @updatePosts ()=>
                @updateInfo ()=>  
                  log "updateInfo: done, total #{@postsCreated} posts added"
                  cb()
          else #nothing to do
            log "no posts"
            imagesTask.load ()=>imagesTask.start()        
        res2tumblog(res)
        
tumStore = tumStore()

resquestQueryDone = ()->
  tumStore.save ()->
    imagesTask.load ()=>
      imagesTask.add tumblog.pic1280,()=>
        imagesTask.start()
        log "tasks processing well."
  #requestImage tumblog.pic1280[0]

res2tumblog = (res)->
  #get posts and images
  if tumblog.postsNumber < res.posts.post.length
    loadNumber = tumblog.postsNumber
  else
    loadNumber = res.posts.post.length
  for i in [0..loadNumber-1]
    post = res.posts.post[i]
    tumblog.posts.push post
    #get images
    if(post && post['photo-url'])
      tumblog.pic1280.push getImage1280 post['photo-url']
  #stop the loop
  return resquestQueryDone() if tumblog.postsNumber<=readNumber+tumblrReadLimited

  #get next 50 posts
  nextNumber = readNumber+tumblrReadLimited
  if nextNumber < tumblog.postsNumber-1
    readNumber=nextNumber
    requestXml()


serverStart = ()->
  requestXml()

serverStart()
#requestImage(testimage)
