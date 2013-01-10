# fluent-plugin-http-list

## Overview

This plugin takes a JSON list of events as input via HTTP POST. If you're
sending a lot of events this can eliminate some overhead. 

※ Note that unlike the default HTTP plugin, this does *not* support msgpack. 

## Configuration

The HttpListInput plugin uses the same settings you would use for the standard
HTTP input plugin. Example:

    <source>
      type http
      port 8888
      bind 0.0.0.0
      body_size_limit 32m
      keepalive_timeout 10s
    </source>

Like the HTTP input plugin, the tag is determined by the URL used, which means 
all events in one request must have the same tag.

## Usage

Have your logging system send JSON lists of events. Example:

    curl -X POST -d 'json=[{"fish":"catfish","user":23},{"fish":"elephantfish","user":23}]' \
      http://localhost:8888/fish.tracker

Each event will go to your output plugins as an individual event. 

## TODO

- MessagePack support (probably as a different plugin)
- Support for time parameter

## Copyright

Copyright:: Copyright (c) 2013 M3, Inc. (written by Paul McCann)
License::   Apache License, Version 2.0
