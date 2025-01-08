#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <src/include.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>

int main(int argc, char **argv) {
  if (argc != 3) {
    ERROR("example: server <ip> <port>");
  };

  char *endptr;
  int port = (int)strtol(argv[2], &endptr, 10);
  if (errno != 0 || *endptr != '\0' || port < 1 || port > 65535) {
    ERROR("Invalid port number (must be 1 - 65535)");
  }

  char buf[65535];

  int sockfd = try(socket(AF_INET, SOCK_DGRAM, 0));

  int optval = 1;
  try(setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, &optval, sizeof(optval)));

  struct sockaddr_in serveraddress = {
      .sin_family = AF_INET,
      .sin_port = htons((unsigned short)port),
  };

  if (inet_pton(AF_INET, argv[1], &serveraddress.sin_addr) != 1) {
    ERROR("Invalid ip address given");
  }

  try(bind(sockfd, (struct sockaddr *)&serveraddress, sizeof(serveraddress)));
  dprint("bound on port: %d\n", port);

  while (1) {
    struct sockaddr_in clientaddr;
    socklen_t clientlen = sizeof(clientaddr);

    int n = try(recvfrom(sockfd, buf, sizeof(buf), 0,
                         (struct sockaddr *)&clientaddr, &clientlen));

    char ipstr[INET6_ADDRSTRLEN];

    if (inet_ntop(AF_INET, &clientaddr.sin_addr, ipstr, sizeof(ipstr)) ==
        NULL) {
      ERROR("Unable to translate client ip address into human format");
    };

    printf("recv: %.*s from %s:%d\n", n, buf, ipstr, clientaddr.sin_port);

    char msg[] = "Welcome to CSE5462.";

    if (sendto(sockfd, msg, strlen(msg), 0, (struct sockaddr *)&clientaddr,
               clientlen) != strlen(msg)) {
      ERROR("Failed to send respose to client");
    };
  }

  return 0;
}
