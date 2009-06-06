#! /opt/local/bin/ruby

require 'rubygems'
require 'mechanize'
require 'google_sites'

sites_path = '/site/YOUR_SITES/'
email = ''
password = ''

gs = GoogleSites.new(sites_path)
gs.login(email, password)

# create "hoge" page.
# https://sites.google.com/site/YOUR_SITES/hoge
new_path = "hoge"
title = "hoge title"
text = "<a href='http://example.com'>Created hoge page</a>"
gs.create(new_path, title, text)