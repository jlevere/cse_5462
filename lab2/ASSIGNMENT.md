# Project #2: JSON Object Transmission

## Objective
Building on project #1, the goal of project #2 is to transition from sending key-value pairs to transmitting serialized JSON objects between a client and a server. You may use my client from project 1 as a starter for your client. You will create both a client and a server for this project. The client will create JSON objects with specific fields, serialize them, and send them over a network. On the server side, the JSON object will be deserialized, and the parsed data will be printed in a human-readable format.

## Client-Side Process

1. **Create JSON Objects**:
   - The client will construct a JSON object containing fields such as (but not limited to):
     - `File_Name`
     - `File_Size`
     - `File_Type`
     - `Date_Created`
     - `Description`
   - Each field will hold a value appropriate for the file being described, such as "Presentation4.otp" for `File_Name` or "4MB" for `File_Size`.

2. **Serialize the JSON Object**:
   - Once the JSON object is created, it needs to be serialized into a string format. Serialization converts the JSON object into a plain text representation that can be transmitted over a network.

3. **Send the JSON Object**:
   - The client will send the serialized JSON string over a UDP socket using `sendto()`. The server, running on a specified port, will be waiting to receive this data.

## Server-Side Process

1. **Receive Serialized Data**:
   - The server will receive the serialized JSON string from the client using `recvfrom()`. This string contains the JSON data in its plain text form.

2. **Deserialize the JSON Object**:
   - After receiving the serialized data, the server will deserialize it back into a JSON object. This process converts the plain text back into a structured JSON format that can be easily manipulated and accessed.

3. **Print the Parsed JSON Data**:
   - The server will then parse the deserialized JSON object and print each key-value pair in a human-readable format. The output should resemble:
     ```
     Parsed JSON data:
     File_Name: "Presentation4.otp"
     File_Size: 4MB
     File_Type: "Presentation"
     Date_Created: "2024-07-05"
     Description: "Webinar slide deck"
     ```

## Key Concepts
- **Serialization**: Converting a JSON object into a string for transmission across a network.
- **Deserialization**: Reconstructing the JSON object from the serialized string on the receiving side.
- **Network Communication**: Using sockets to send and receive data between client and server.
  - In this project, UDP sockets (`sendto()` and `recvfrom()`) are used for communication.

## Technical Requirements
- The client will construct a JSON object with the required fields, serialize it, and send it to the server.
- The server will listen for incoming serialized JSON data, deserialize the JSON object, and print it out in a structured format.

## Example Fields in the JSON Object
- `File_Name`: Name of the file (e.g., "Presentation4.otp").
- `File_Size`: Size of the file (e.g., "4MB").
- `File_Type`: Type of the file (e.g., "Presentation").
- `Date_Created`: Creation date of the file (e.g., "2024-07-05").
- `Description`: A brief description of the file (e.g., "Webinar slide deck").

## Expected Output on the Server
Upon receiving and parsing the JSON object, the server should display each key-value pair in the format shown below: