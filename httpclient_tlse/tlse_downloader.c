#include <stdio.h>
#include <sys/types.h>
#ifdef _WIN32
#include <winsock2.h>
#define socklen_t int
#else
#include <sys/socket.h>
#include <netinet/in.h>
#include <netdb.h>
#endif
#include "tlse/tlse.c"
#include "tlse_downloader.h"
#include <string.h>

// ================================================================================================= //
// this example ilustrates the libssl-almost-compatible interface                                    //
// tlslayer.c exports libssl compatibility APIs. Unlike tlslayer low-level apis, the SSL_* interface //
// is blocking! (or depending of the underling socket).                                              //
// ================================================================================================= //

// optional callback function for peer certificate verify
int verify(struct TLSContext *context, struct TLSCertificate **certificate_chain, int len) {
    int i;
    int err;
    if (certificate_chain) {
        for (i = 0; i < len; i++) {
            struct TLSCertificate *certificate = certificate_chain[i];
            // check validity date
            err = tls_certificate_is_valid(certificate);
            if (err)
                return err;
            // check certificate in certificate->bytes of length certificate->len
            // the certificate is in ASN.1 DER format
        }
    }
    // check if chain is valid
    err = tls_certificate_chain_is_valid(certificate_chain, len);
    if (err)
        return err;

    const char *sni = tls_sni(context);
    if ((len > 0) && (sni)) {
        err = tls_certificate_valid_subject(certificate_chain[0], sni);
        if (err)
            return err;
    }

    // Perform certificate validation agains ROOT CA
    err = tls_certificate_chain_is_valid_root(context, certificate_chain, len);
    if (err)
        return err;

    return no_error;
}
int verify_stub(struct TLSContext *context, struct TLSCertificate **certificate_chain, int len) {
    int i;
    if (certificate_chain) {
        for (i = 0; i < len; i++) {
            struct TLSCertificate *certificate = certificate_chain[i];
            // check certificate ...
        }
    }
    //return certificate_expired;
    //return certificate_revoked;
    //return certificate_unknown;
    return no_error;
}

int getContent(char **result, char *url) {
  // first, parse the url to get hostname and request (everything following hostname)
  //printf("got url: '%s'\n",url);
  char * slash_loc_ptr = url;
  // find end of https:// (second slash)
  for (int i=0; i<2; i++) {
    slash_loc_ptr = strchr(slash_loc_ptr+1, '/');
    if (slash_loc_ptr == NULL) return -8; // RETERROR BAD URL STRING
  }
  char * ptr_host_begin = slash_loc_ptr+1;
  // find  end of host https://*/ (third slash)
  slash_loc_ptr = strchr(slash_loc_ptr+1, '/');
  if (slash_loc_ptr == NULL) return -8; // RETERROR BAD URL STRING
  char * ptr_host_end = slash_loc_ptr;
  int host_name_len = 0;
  if (ptr_host_end == NULL) {
    host_name_len = strlen(ptr_host_begin);
  } else {
    host_name_len = ptr_host_end-ptr_host_begin;
  }
  char * host_name = malloc(host_name_len+1);
  strncpy(host_name, ptr_host_begin, host_name_len);
  host_name[host_name_len] = '\0';
  //printf("hostname: '%s'\n",host_name);
  int request_len = 0;
  char * request;
  // if no request after hostname, then make it just a slash
  if (ptr_host_end == NULL) {
    request = malloc(2);
    request[0] = '/';
    request_len = 1;
  } else { // otherwise grab all data after the hostname, including the slash
    request_len = strlen(ptr_host_end); // the request is everything after the hostname
    request = malloc(request_len+1);
    strncpy(request, ptr_host_end, request_len);
  }
  request[request_len] = '\0';

  int sockfd, portno, n;
  struct sockaddr_in serv_addr;
  struct hostent *server;
  int ret;
  char msg[] = "GET %s HTTP/1.1\r\nHost: %s:%i\r\nConnection: close\r\n\r\n";
  char msg_buffer[0xFF];
  char buffer[0xFFF];
  char root_buffer[0xFFFFF];
#ifdef _WIN32
  // Windows: link against ws2_32.lib
  WSADATA wsaData;
  WSAStartup(MAKEWORD(2, 2), &wsaData);
#else
  // ignore SIGPIPE
  signal(SIGPIPE, SIG_IGN);
#endif

  // dummy functions ... for semantic compatibility only
  SSL_library_init();
  SSL_load_error_strings();

  // note that SSL and SSL_CTX are the same in tlslayer.c
  // both are mapped to TLSContext
  SSL *clientssl = SSL_CTX_new(SSLv3_client_method());

  // =========================================================================== //
  // IMPORTANT NOTE:
  // SSL_new(clientssl) MUST never be called
  // SSL_CTX_new returns a SSL handle, instead of a SSL_CTX object (like libssl)
  // =========================================================================== //

  // optionally, we can set a certificate validation callback function
  // if set_verify is not called, and root ca is set, `tls_default_verify`
  // will be used (does exactly what `verify` does in this example)
  SSL_CTX_set_verify(clientssl, SSL_VERIFY_PEER, verify_stub);

  if (!clientssl) {
    //fprintf(stderr, "Error initializing client context\n");
    return -1; // RETERROR INITIALIZING SSL CLIENT CONTEXT
  }

  portno = 443;

  sockfd = socket(AF_INET, SOCK_STREAM, 0);
  if (sockfd < 0) {
    //fprintf(stderr, "ERROR opening socket");
    return -2; // RETERROR OPENING SOCKET
  }
  server = gethostbyname(host_name);
  if (server == NULL) {
    //fprintf(stderr, "ERROR, no such host\n");
    return -3; // RETERROR NO SUCH HOST
  }
  memset((char *) &serv_addr, 0, sizeof(serv_addr));
  serv_addr.sin_family = AF_INET;
  memcpy((char *)&serv_addr.sin_addr.s_addr, (char *)server->h_addr, server->h_length);
  serv_addr.sin_port = htons(portno);
  if (connect(sockfd,(struct sockaddr *)&serv_addr,sizeof(serv_addr)) < 0) {
    //fprintf(stderr, "ERROR connecting to %s", host_name);
    return -4; // RETERROR ESTABLISHING CONNECTION
  }
  snprintf(msg_buffer, sizeof(msg_buffer), msg, request, host_name, portno);
  // starting from here is identical with libssl
  SSL_set_fd(clientssl, sockfd);

  // set sni
  tls_sni_set(clientssl,host_name);

  if ((ret = SSL_connect(clientssl)) != 1) {
    //fprintf(stderr, "Handshake Error %i\n", ret);
    return -5; // RETERROR SSL HANDSHAKE ERROR
  }
  ret = SSL_write(clientssl, msg_buffer, strlen(msg_buffer));
  if (ret < 0) {
    //fprintf(stderr, "SSL write error %i\n", ret);
    return -6; // RETERROR SSL WRITE ERROR
  }
  // print result to screen
  int contents_capacity = 0xFFF;
  int contents_len = 0;
  char * contents = malloc(contents_capacity);
  // get data chunks from server and stitch them together like a std::vector grows
  while ((ret = SSL_read(clientssl, buffer, sizeof(buffer))) > 0) {
    if (ret < 0) {
      //fprintf(stderr, "SSL read error %i\n", ret);
      return -7; // RETERROR SSL READ ERROR
    }
    int len = ret;
    // resize destination contents buffer if needed first
    if (contents_len + len + 1 > contents_capacity) {
      char * new_contents = malloc(contents_capacity << 1);
      memcpy(new_contents, contents, contents_len);
      free(contents);
      contents = new_contents;
      contents_capacity <<= 1;
    }
    // copy buffer 
    memcpy(contents+contents_len, buffer, len);
    contents_len += len;
  }
  // finish string
  contents[contents_len] = '\0';
  if (ret < 0) {
    //fprintf(stderr, "SSL read error %i\n", ret);
    return -7; // RETERROR SSL READ ERROR
  }
  //fwrite(contents, contents_len, 1, stdout);

  SSL_shutdown(clientssl);
#ifdef _WIN32
  closesocket(sockfd);
#else
  close(sockfd);
#endif
  SSL_CTX_free(clientssl);

  free(host_name);
  free(request);

  // find after the response headers where the actual content starts
  char * contents_after_headers = strstr(contents,"\r\n\r\n")+4;
  int contents_after_headers_len = contents_len - /*pointer location differences*/(contents_after_headers-contents);

  (*result) = malloc(contents_after_headers_len);
  memcpy((*result), contents_after_headers, contents_after_headers_len);
  (*result)[contents_after_headers_len] = '\0';
  free(contents);
  return contents_after_headers_len;
}

int downloadFile(char *url, char *filename) {

  char * content;
  int len = getContent(&content, url);

  if (len < 0) return len; // had an ERROR RETCODE

  // write data to file
  FILE* outfile = fopen(filename,"wb");
  fwrite(content, len, 1, outfile);
  fclose(outfile);

  free(content);

  return(0);
}
