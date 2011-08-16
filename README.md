tumblerBackupCoffee 0.0.1
============

## What's tumblerBackupCoffee?

tumblerBackupCoffee is a tumblr backup tools in cooffeescript, node.js and mongodb.

## How to use

  start mongodb server

  coffee server.coffee

## Config
  env: development || production
  tumblrDomain: xxx.tumblr.com
  writeLocalImageFile: write a local image file when fetched
  proxy: ..

##中文流程说明

0 检查有没有图片队列要处理
1 用tumblr v1 api 读取 xml ，每次读50条，直到全部读取完
2 将帖子信息存到数据库
3 生成图片队列
4 抓取图片（单队列抓取）
5 将图片信息存到gridfs


## Credits

[sjerrys](http://github.com/sjerrys) 
[微博](http://weibo.com/sunchen)
