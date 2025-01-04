### Objective
The goal of this lab is to familiarize students with client/server programming using datagram sockets in C. Students will create a simple client and server application that communicates via the university’s Linux systems.

### Overview:
In this lab, students will:
1. Write a client program that sends the message "Hello, World!" to the server.
2.  Write a server program that responds with the message "Welcome to CSE5462."
3.  Use datagram sockets (UDP) for communication between the client and server.
4.  Create a Makefile for compiling the client and server programs, including a make clean option.

### Learning Objectives:
By the end of this lab, students will:
1.	Understand the basics of socket programming in C.
2.	Learn to work with datagram sockets (UDP) for communication.
3.	Practice writing and organizing C programs for client/server communication.
4.	Gain experience using Makefiles to compile programs efficiently.
5.	Familiarize themselves with developing and running C programs on university Linux systems.

## Requirements:

1.	Client Program:
    - Sends the message "Hello, World!" to the server.
    - Exits after receiving the server’s response.
2.	Server Program:
    - Receives the message from the client.
    - Responds with "Welcome to CSE5462."
    - Runs continuously, waiting for messages from clients.
3.	Makefile:
    - Includes targets to compile both the client and server programs.
    - Provides a make clean option to remove compiled binaries and temporary files.
4.	Environment:
    - Programs must be written in C.
    - Programs must run on the university’s Linux systems.

### Implementation Steps:

1. Setup
   - Create a directory for your lab files.
   - Use your preferred editor (e.g., vim, nano, or gedit) to write the client and server programs.
2. Client Program
   - Use the socket(), sendto(), and recvfrom() system calls for communication.
   - The client should:
        1.	Create a socket.
        2.	Send "Hello, World!" to the server.
        3.	Wait for the server’s response.
        4.	Print the response and exit.

3. Server Program
   - Use the socket(), bind(), recvfrom(), and sendto() system calls for communication.
   - The server should:
        1.	Create a socket.
        2.	Bind it to a specific port.
        3.	Wait for incoming messages from clients.
        4.	Respond with "Welcome to CSE5462."
        5.	Continue running indefinitely, handling multiple client requests.
4. Makefile
   - Create a Makefile with the following targets:
        - `all`: Compiles both client and server programs.
        - `clean`: Removes all compiled binaries and temporary files.

## Submission:
Submit the following files:
1.	client.c - Source code for the client program.
2.	server.c - Source code for the server program.
3.	Makefile - File to compile and clean your programs.
4.	README.txt - Brief instructions on how to run the programs.


### Evaluation Criteria:
   - Correctness of the client and server communication.
   - Proper use of datagram sockets.
   - Well-structured and commented code.
   - Functionality of the Makefile.
   - Programs must compile and run on the university Linux systems.

## Additional Notes:
   - Use the man pages (e.g., man socket, man sendto) for detailed information on system calls.
   - Test your programs thoroughly to ensure reliable communication.
   - Adhere to good programming practices, including meaningful variable names and comments.
   - Reach out to the instructor or TAs if you have any questions or face issues.


### Sample Output:
1.	Client:
2.	Sending message to server: Hello, World!
Received response from server: Welcome to CSE5462.
3.	Server:
4.	Received message from client: Hello, World!
Responded with: Welcome to CSE5462.
