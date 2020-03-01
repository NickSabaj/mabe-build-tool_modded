
type
 SSLInitializeError* = object of Exception
 SSLOpeningSocketError* = object of Exception
 SSLNoSuchHostError* = object of Exception
 SSLEstablishingConnectionError* = object of Exception
 SSLHandshakeError* = object of Exception
 SSLWriteError* = object of Exception
 SSLReadError* = object of Exception
 SSLBadURLStringError* = object of Exception

proc raise_ssl_error(error_code:int) =
  if error_code < 0:
    case error_code:
      of -1: raise newException(SSLInitializeError, "Unable to initialize SSL client")
      of -2: raise newException(SSLOpeningSocketError, "Unable to open SSL socket")
      of -3: raise newException(SSLNoSuchHostError, "No such host")
      of -4: raise newException(SSLEstablishingConnectionError, "Unable to establish an SSL connection to host")
      of -5: raise newException(SSLHandshakeError, "SSL Handshake failed")
      of -6: raise newException(SSLWriteError, "SSL stream write error")
      of -7: raise newException(SSLReadError, "SSL stream read error")
      of -8: raise newException(SSLBadURLStringError, "Bad URL string")
      else: discard

proc cdownloadFile(url:cstring, filename:cstring):cint {.header: "httpclient_tlse/tlse_downloader.h", importc: "downloadFile".}

proc downloadFile*(url:string, filename:string) =
  let error_code = cdownloadFile(url, filename)
  raise_ssl_error(error_code)

proc cgetContent(result:ptr ptr char, url:cstring):cint {.header: "httpclient_tlse/tlse_downloader.h", importc: "getContent".}

proc getContent*(url:string):string = 
  var contents = cast[ptr ptr char](alloc sizeof(ptr char))
  let error_code = cgetContent(contents, url)
  raise_ssl_error(error_code)
  result = $contents[]
  dealloc contents

{.passC: "-DTLS_AMALGAMATION".}
{.compile: "httpclient_tlse/tlse_downloader.c".}

