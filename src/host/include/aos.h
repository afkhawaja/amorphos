#ifndef aos_h__
#define aos_h__
// Normal includes
#include <sys/types.h>
#include <sys/stat.h>
#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <errno.h>
#include <unistd.h>
#include <syslog.h>
#include <string.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <sys/un.h>
#include <unistd.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdarg.h>
#include <assert.h>
#include <string>
#include <sstream>
#include <iostream>
#include <map>
#include <queue>

#define SOCKET_NAME "/tmp/aos_daemon.socket"
#define SOCKET_FAMILY AF_UNIX
#define SOCKET_TYPE SOCK_STREAM

#define BACKLOG 128

using session_id_t = uint64_t;

enum class aos_socket_command {
    INTIATE_SESSION,
    END_SESSION,
    CNTRLREG_READ_REQUEST,
    CNTRLREG_READ_RESPONSE,
    CNTRLREG_WRITE_REQUEST,
    CNTRLREG_WRITE_RESPONSE,
    BULKDATA_READ_REQUEST,
    BULKDATA_READ_RESPONSE,
    BULKDATA_WRITE_REQUEST,
    BULKDATA_WRITE_RESPONSE,
    QUIESCENCE_REQ_REQUEST,
    QUIESCENCE_REQ_RESPONSE,
    QUIESCENCE_CHECK_REQUEST,
    QUIESCENCE_CHECK_RESPONSE     
};


enum class aos_errcode {
    SUCCESS = 0,
    RETRY,
    ZERO_SIZE_TRANSFER,
    ALIGNMENT_FAILURE,
    PROTECTION_FAILURE,
    APP_DOES_NOT_EXIST,
    INVALID_SESSION_ID,
    TIMEOUT,
    SOCKET_FAILURE,
    INVALID_REQUEST,
    QUIESCENCE_UNAVAILABLE,
    UNKNOWN_FAILURE
};

struct aos_socket_command_packet {
    aos_socket_command command_type;
    session_id_t session_id;
    uint64_t addr64;
    uint64_t data64;
    uint64_t numBytes;
    char     char_buf[256];
};

struct aos_socket_response_packet {
    aos_errcode errorcode;
    uint64_t    data64;
    uint64_t    numBytes;
    session_id_t session_id;
};

class aos_client {
public:

    aos_client(std::string app_name) :
        app_name(app_name),
        session_id(~0x0),
        connection_socket(0),
        connectionOpen(false),
        intialized(false)
    {
        // Setup the struct needed to connect the aos daemon
        memset(&socket_name, 0, sizeof(struct sockaddr_un));
        socket_name.sun_family = SOCKET_FAMILY;
        strncpy(socket_name.sun_path, SOCKET_NAME, sizeof(socket_name.sun_path) - 1);
    }

    aos_errcode aos_init_session() {
        assert(!intialized);
        // Open the socket
        openSocket();
        // Create the packet
        aos_socket_command_packet cmd_pckt;
        cmd_pckt.command_type = aos_socket_command::INTIATE_SESSION;
        // Copy the app name into the char_buf
        strncpy(cmd_pckt.char_buf, app_name.c_str(), app_name.length());
        cmd_pckt.char_buf[app_name.length()] = '\0';
        // send over the request
        writeCommandPacket(cmd_pckt);
        // read the response packet
        aos_socket_response_packet resp_pckt;
        readResponsePacket(resp_pckt);
        // close the socket
        closeSocket();
        // check if we established a session
        if (resp_pckt.errorcode != aos_errcode::SUCCESS) {
            // we were NOT given a session id
            assert(false);
        }
        // Save session id
        session_id = resp_pckt.session_id;
        intialized = true;
        return aos_errcode::SUCCESS;
    }
 
    aos_errcode aos_end_session() {
        assert(intialized);
        // Open the socket
        openSocket();
        // Create the packet
        aos_socket_command_packet cmd_pckt;
        cmd_pckt.command_type = aos_socket_command::END_SESSION;
        cmd_pckt.session_id   = session_id;
        // Send over the request
        writeCommandPacket(cmd_pckt);
        // close socket
        closeSocket();
        // Return success/error condition
        return aos_errcode::SUCCESS;
    }

    aos_errcode aos_cntrlreg_write(uint64_t addr, uint64_t value) {
        assert(intialized);
        // Open the socket
        openSocket();
        // Create the packet
        aos_socket_command_packet cmd_pckt;
        cmd_pckt.command_type = aos_socket_command::CNTRLREG_WRITE_REQUEST;
        cmd_pckt.session_id = session_id;
        cmd_pckt.addr64 = addr;
        cmd_pckt.data64 = value;
        // Send over the request
        writeCommandPacket(cmd_pckt);
        // read the response packet
        aos_socket_response_packet resp_pckt;
        readResponsePacket(resp_pckt);
        // close socket
        closeSocket();
        // Return success/error condition
        return resp_pckt.errorcode;
    }

    aos_errcode aos_cntrlreg_read(uint64_t addr, uint64_t & value) {
        assert(intialized);
        aos_errcode errorcode = aos_cntrlreg_read_request(addr);
        if (errorcode != aos_errcode::SUCCESS) {
        	return errorcode;
        }
        // do some error checking
        errorcode = aos_cntrlreg_read_response(value);
        return errorcode;
    }

    aos_errcode aos_cntrlreg_read_request(uint64_t addr) {
        assert(intialized);
        // Open the socket
        openSocket();
        // Create the packet
        aos_socket_command_packet cmd_pckt;
        cmd_pckt.command_type = aos_socket_command::CNTRLREG_READ_REQUEST;
        cmd_pckt.session_id = session_id;
        cmd_pckt.addr64 = addr;
        // Send over the request
        writeCommandPacket(cmd_pckt);
        // read the response packet
        aos_socket_response_packet resp_pckt;
        readResponsePacket(resp_pckt);
        // close socket
        closeSocket();
        // Return success/error condition
        return resp_pckt.errorcode;
    }

    aos_errcode aos_cntrlreg_read_response(uint64_t & value) {
        assert(intialized);
        // Open the socket
        openSocket();
        // Create the packet
        aos_socket_command_packet cmd_pckt;
        cmd_pckt.command_type = aos_socket_command::CNTRLREG_READ_RESPONSE;
        cmd_pckt.session_id = session_id;
        // send over the request
        writeCommandPacket(cmd_pckt);
        // read the response packet
        aos_socket_response_packet resp_pckt;
        readResponsePacket(resp_pckt);
        // close the socket
        closeSocket();
        // copy over the data
        value = resp_pckt.data64;

        return aos_errcode::SUCCESS;
    }

    aos_errcode aos_bulkdata_write(uint64_t addr, size_t numBytes, void * buf) {
        assert(intialized);
        assert(numBytes > 0);
        // Open the socket
        openSocket();
        // Create the command packet
        aos_socket_command_packet cmd_pckt;
        cmd_pckt.command_type = aos_socket_command::BULKDATA_WRITE_REQUEST;
        cmd_pckt.session_id = session_id;
        cmd_pckt.addr64 = addr;
        cmd_pckt.numBytes = numBytes;
        // send over the request
        writeCommandPacket(cmd_pckt);
        // read response packet
        aos_socket_response_packet resp_pckt;
        readResponsePacket(resp_pckt);
        // See if we can proceed to send data over
        if (resp_pckt.errorcode != aos_errcode::SUCCESS) {
            closeSocket();
            return resp_pckt.errorcode;
        }
        // Send data over
        writeBulkData(numBytes, buf);
        // close the socket
        closeSocket();
        return aos_errcode::SUCCESS;
    }

    aos_errcode aos_bulkdata_read_request(uint64_t addr, size_t numBytes) {
        assert(intialized);
        assert(numBytes > 0);
        // Open the socket
        openSocket();
        // Create the command packet
        aos_socket_command_packet cmd_pckt;
        cmd_pckt.command_type = aos_socket_command::BULKDATA_READ_REQUEST;
        cmd_pckt.session_id = session_id;
        cmd_pckt.addr64 = addr;
        cmd_pckt.numBytes = numBytes;        
        // send over the request
        writeCommandPacket(cmd_pckt);
        // read response packet
        aos_socket_response_packet resp_pckt;
        readResponsePacket(resp_pckt);
        if (resp_pckt.errorcode != aos_errcode::SUCCESS) {
            closeSocket();
            return resp_pckt.errorcode;
        }
        // close the socket
        closeSocket();
        return aos_errcode::SUCCESS;
    }

    aos_errcode aos_bulkdata_read_response(void * buf) {
        assert(intialized);
        // Open the socket
        openSocket();
        // Create the command packet
        aos_socket_command_packet cmd_pckt;
        cmd_pckt.command_type = aos_socket_command::BULKDATA_READ_RESPONSE;
        cmd_pckt.session_id = session_id;
        // send over the request
        writeCommandPacket(cmd_pckt);
        // read response packet
        aos_socket_response_packet resp_pckt;
        readResponsePacket(resp_pckt);
        if (resp_pckt.errorcode != aos_errcode::SUCCESS) {
            closeSocket();
            return resp_pckt.errorcode;
        }
        // Receive the data from
        uint64_t numBytes = resp_pckt.numBytes;
        if (read(connection_socket, buf, numBytes) == -1) {
        	closeSocket();
        	return aos_errcode::SOCKET_FAILURE;
        }

        // close the socket
        closeSocket();
        return aos_errcode::SUCCESS;
    }

    aos_errcode aos_quiescence_request() {
        //aos_errcode errorcode = aos_cntrlreg_write(0x1FF8, 1);  // TODO: maybe not hardcode in these addresses
        //return errorcode;

        assert(intialized);
        // Open the socket
        openSocket();
        // Create the packet
        aos_socket_command_packet cmd_pckt;
        cmd_pckt.command_type = aos_socket_command::QUIESCENCE_REQ_REQUEST;
        cmd_pckt.session_id = session_id;
        cmd_pckt.addr64 = 0x0;
        cmd_pckt.data64 = 1;
        // Send over the request
        writeCommandPacket(cmd_pckt);
        // read the response packet
        aos_socket_response_packet resp_pckt;
        readResponsePacket(resp_pckt);
        // close socket
        closeSocket();
        // Return success/error condition
        return resp_pckt.errorcode;
    }
    
    aos_errcode aos_quiescence_check(bool & quiesced) {
        //uint64_t quiesced_val;
        //aos_errcode errorcode = aos_cntrlreg_read(0x1FF0, quiesced_val);
        //if (errorcode != aos_errcode::SUCCESS) {
        //    return errorcode;
        //}
        //
        //if (quiesced_val == 0) {
        //    quiesced = false;
        //} else if (quiesced_val == 1) {
        //    quiesced = true;
        //} else {
        //    return aos_errcode::UNKNOWN_FAILURE;
        //}
        //
        //return errorcode;

        assert(intialized);
        aos_errcode errorcode = aos_quiescence_check_request();
        if (errorcode != aos_errcode::SUCCESS) {
        	return errorcode;
        }
        // do some error checking
        errorcode = aos_quiescence_check_response(quiesced);
        return errorcode;
    }

    aos_errcode aos_quiescence_check_request() {
        assert(intialized);
        // Open the socket
        openSocket();
        // Create the packet
        aos_socket_command_packet cmd_pckt;
        cmd_pckt.command_type = aos_socket_command::QUIESCENCE_CHECK_REQUEST;
        cmd_pckt.session_id = session_id;
        cmd_pckt.addr64 = 0x0;
        // Send over the request
        writeCommandPacket(cmd_pckt);
        // read the response packet
        aos_socket_response_packet resp_pckt;
        readResponsePacket(resp_pckt);
        // close socket
        closeSocket();
        // Return success/error condition
        return resp_pckt.errorcode;
    }

    aos_errcode aos_quiescence_check_response(bool & quiesced) {
        assert(intialized);
        // Open the socket
        openSocket();
        // Create the packet
        aos_socket_command_packet cmd_pckt;
        cmd_pckt.command_type = aos_socket_command::QUIESCENCE_CHECK_RESPONSE;
        cmd_pckt.session_id = session_id;
        // send over the request
        writeCommandPacket(cmd_pckt);
        // read the response packet
        aos_socket_response_packet resp_pckt;
        readResponsePacket(resp_pckt);
        // close the socket
        closeSocket();
        // copy over the data
        uint64_t quiesced_val = resp_pckt.data64;
        if (quiesced_val == 0) {
            quiesced = false;
        } else if (quiesced_val == 1) {
            quiesced = true;
        } else {
            return aos_errcode::UNKNOWN_FAILURE;
        }

        return aos_errcode::SUCCESS;
    }
    

    aos_errcode aos_bulkdata_read(uint64_t addr, size_t numBytes, void * buf) {
        assert(intialized);
        // Open the socket
        aos_errcode errorcode = aos_bulkdata_read_request(addr, numBytes);
        if (errorcode != aos_errcode::SUCCESS) {
            return errorcode;
        }
        // do some error checking
        errorcode = aos_bulkdata_read_response(buf);
        return errorcode;
    }

    void printError(std::string errStr) {
        std::cout << errStr << std::endl;
    }

    uint64_t getSessionId() const {
        assert(intialized);
        return session_id;
    }

private:
    sockaddr_un socket_name;
    std::string app_name;
    uint64_t session_id;
    int connection_socket;
    bool connectionOpen;
    bool intialized;

    void openSocket() {
        if (connectionOpen)  {
            printError("Can't open already open socket");
        }
        connection_socket = socket(SOCKET_FAMILY, SOCKET_TYPE, 0);
        if (connection_socket == -1) {
           perror("client socket");
           exit(EXIT_FAILURE);
        }

        if (connect(connection_socket, (sockaddr *) &socket_name, sizeof(sockaddr_un)) == -1) {
            perror("client connection");
        }
        connectionOpen = true;
    }

    void closeSocket() {
        if (!connectionOpen) {
            printError("Can't close a socket that isn't open");
        }
        if (close(connection_socket) == -1) {
            perror("close error on client");
        }
        connectionOpen = false;
    }

    int writeCommandPacket(aos_socket_command_packet & cmd_pckt) {
        if (!connectionOpen) {
            printError("Can't write command packet without an open socket");
        }
        if (write(connection_socket, &cmd_pckt, sizeof(aos_socket_command_packet)) == -1) {
            printf("Client %ld: Unable to write to socket\n", session_id);
            perror("Client write");
        }
        // return success/error
        return 0;
    }

    int readResponsePacket(aos_socket_response_packet & resp_pckt) {
        if (!connectionOpen) {
            printError("Can't close a socket that isn't open"); 
        }
        if (read(connection_socket, &resp_pckt, sizeof(aos_socket_response_packet)) == -1) {
            perror("Unable to read respone packet from daemon");
        }
        return 0;
    }

    int writeBulkData(uint64_t numBytes, void * buf_ptr) {
        if (!connectionOpen) {
            printError("Can't write data packet without an open socket");
        }
        if (write(connection_socket, buf_ptr, numBytes) == -1) {
            printf("Client %ld: Unable to write to socket\n", session_id);
            perror("Client write");
        }
        // return success/error
        return 0;
    }

    /*uint64_t calcNumBulkDataPackets(uint64_t numBytes) {
        if (numBytes <= BYTES_PER_BULK_PACKET) {
            return 1;
        }
        // We know we are at least one byte over a single full packet
        uint64_t full_packets = numBytes / BYTES_PER_BULK_PACKET;
        if ((full_packets * BYTES_PER_BULK_PACKET) == numBytes) {
            return full_packets;
        } else {
            // need at least one extra packet
            return full_packets + 1;
        }
    }*/

};

#endif // end aos_h__
