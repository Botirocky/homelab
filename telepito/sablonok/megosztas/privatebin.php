;<?php http_response_code(403); /*
[main]
name = "Park Paste"
discussion = true
opendiscussion = false
password = true
fileupload = true
burnafterreadingselected = false
defaultformatter = "markdown"
sizelimit = 10485760
template = "bootstrap5"
languageselection = false
languagedefault = "hu"
qrcode = true
email = true
icon = "identicon"
zerobincompatibility = false
httpwarning = false
compression = "zlib"

[expire]
default = "1week"

[expire_options]
5min = 300
10min = 600
1hour = 3600
1day = 86400
1week = 604800
1month = 2592000
1year = 31536000
never = 0

[formatter_options]
plaintext = "Plain Text"
syntaxhighlighting = "Source Code"
markdown = "Markdown"

[traffic]
limit = 10

[purge]
limit = 300
batchsize = 10

[model]
class = Filesystem
[model_options]
dir = PATH "data"
