#! /opt/local/bin/ruby

require 'rubygems'
require 'mechanize'
require 'google_sites'

path = '/site/YOUR_SITES/'
email = ''
password = ''

gs = GoogleSites.new(path)
gs.login(email, password)

path_name = "hoge"
title = "hoge title"
text = "<a href='http://example.com'>Create hoge page</a>"
gs.create(path_name, title, text)
