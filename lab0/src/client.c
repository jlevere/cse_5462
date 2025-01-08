#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <src/include.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/types.h>

int main(int argc, char **argv) {
  if (argc != 3) {
    ERROR("example: client <ip> <port>");
  };

  char *endptr;
  int port = (int)strtol(argv[2], &endptr, 10);
  if (errno != 0 || *endptr != '\0' || port < 1 || port > 65535) {
    ERROR("Invalid port number (must be between 1 and 65535)");
  }

  int sockfd = try(socket(AF_INET, SOCK_DGRAM, 0));

  struct timeval timeout = {.tv_sec = 5, .tv_usec = 0};
  try(setsockopt(sockfd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout)));

  struct sockaddr_in serveraddress = {
      .sin_family = AF_INET,
      .sin_port = htons((unsigned short)port),
  };

  if (inet_pton(AF_INET, argv[1], &serveraddress.sin_addr) != 1) {
    ERROR("IP wrong format");
  };

  socklen_t serveraddrlen = sizeof(serveraddress);

  char msg[] = "Hello, World!";

  if (sendto(sockfd, msg, strlen(msg), 0, (struct sockaddr *)&serveraddress,
             serveraddrlen) != strlen(msg)) {
    ERROR("Failed to send message to server");
  };

  char buf[65535];
  int n;
  while ((n = try(recvfrom(sockfd, buf, sizeof(buf), 0,
                           (struct sockaddr *)&serveraddress,
                           &serveraddrlen))) < 0) {
    if (errno != EAGAIN && errno != EWOULDBLOCK) {
      ERROR("Receive failed");
    }
    sleep(1);
  }
  printf("Server: %.*s\n", n, buf);

  return 0;
}