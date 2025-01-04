# Project 1: Multicast Server for Receiving and Printing Key-Value Pairs in C

## Objective  
In this project, you will implement a server that listens for key-value pair messages over multicast. The server will join a multicast group, receive messages from a client, and print out the key-value pairs in a formatted manner. The key can be any string without spaces, and the value can be either an integer or a string enclosed in double quotes. The output should be formatted with each key and value printed in a 20-character field.

---

## What You'll Learn  

1. **Socket Programming for Servers**  
   You will write a server that uses UDP sockets to receive messages over multicast. This involves creating and binding a socket, joining a multicast group, and receiving data from the network.

2. **Handling Key-Value Pairs**  
   You will parse messages in the format of key-value pairs, where the key is a string without spaces and the value can be an integer or a string (strings are enclosed in quotes).

3. **Multicast Networking**  
   By using multicast, your server will receive messages simultaneously with other servers listening on the same group and port, simulating one-to-many communication.

4. **Formatted Output**  
   You will format and print the received key-value pairs in aligned columns, ensuring both the key and value are displayed in fields of 20 characters each.

---

## Project Overview  

1. **Write the Server:**  
   - The server will create a UDP socket, bind it to a specific port, and join a multicast group.  
   - It will listen for incoming messages from the client in the form of key-value pairs.  
   - The key can be any string without spaces (e.g., `File_Name`, `File_Size`, etc.), and the value can be a string enclosed in quotes or a number (e.g., `"Document1.txt"`, `12KB`).  
   - The server will parse the received message, validate the format, and print each key-value pair in a neatly aligned format, with 20 characters allocated to each field.

2. **Example Input:**  
   The client may send a single message containing multiple key-value pairs, such as:  
```
File_Name:"Document1.txt" File_Size:12KB File_Type:"Text" Date_Created:"2023-10-01" Description:"Report for Q3 financials"
```

3. **Formatted Output:**  
The server should print each key-value pair on a new line, ensuring both the key and the value are left-aligned and occupy 20 characters each, like so:  

```
File_Name       Document1.txt
File_Size       12KB
File_Type       Text
Date_Created    2023-10-01
Description     Report for Q3 financials
```


---

## Key Concepts to Explore  

- **Multicast Communication:**  
Multicast allows multiple servers to receive the same message simultaneously by listening on the same multicast address and port. This efficient one-to-many communication model reduces redundant transmissions.

- **String Parsing:**  
You will handle string parsing to extract keys and values from incoming messages, ensuring proper formatting. Keys will be strings without spaces, and values will either be strings enclosed in quotes or numerical values.

- **Output Formatting:**  
You will practice formatting output by ensuring that each key-value pair is printed in a field of 20 characters, with proper alignment to maintain readability.

---

## Deliverables  

- A server program in C that:  
- Creates a UDP socket, joins a multicast group, and listens on a specific port.  
- Receives messages containing key-value pairs in the specified format.  
- Parses the key-value pairs, validates the input, and prints each pair with the key and value aligned in 20-character fields.

---

## Formatting Requirements  

- Each key-value pair should be printed on a separate line.  
- Both the key and value should be left-aligned and occupy 20 characters each.  

### Example Output:  

```
File_Name       Document1.txt
File_Size       12KB
File_Type       Text
Date_Created    2023-10-01
Description     Report for Q3 financials
```
