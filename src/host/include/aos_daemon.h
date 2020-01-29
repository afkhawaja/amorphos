#include "aos_app_session.h"
//#include "aos_fpga_handle.h"
#include "aos_scheduler.h"


enum DMA_OPERATION {
    WRITE,
    READ
};

class aos_host {
public:

    const static uint16_t pci_vendor_id = 0x1D0F; /* Amazon PCI Vendor ID */
    const static uint16_t pci_device_id = 0xF000; /* PCI Device ID preassigned by Amazon for F1 applications */


    aos_host(uint64_t num_fpgas, bool dummy) :
        num_fpga(num_fpgas),
        isDummy(dummy),
        lazy_reads(false)
    {
        assert(num_fpga > 0);

        // intialize fpga metadata
        for (uint64_t fpga_id = 0; fpga_id < num_fpga; fpga_id++) {
            bar1_attached.push_back(false);
            bar4_attached.push_back(false);
            pci_bar1_handle.push_back(PCI_BAR_HANDLE_INIT);
            pci_bar4_handle.push_back(PCI_BAR_HANDLE_INIT);
            interfaces_enabled.push_back(false);
            slot_session_map.push_back(std::map<uint64_t, aos_app_session *>());
            slot_appid_map.push_back(std::map<uint64_t, std::string>());
            xdma_write_channel[fpga_id] = 0;
            xdma_read_channel[fpga_id]  = 0;
        }
        // Socket stuff
        memset(&socket_name, 0, sizeof(sockaddr_un));
        socket_name.sun_family = AF_UNIX;
        strncpy(socket_name.sun_path, SOCKET_NAME, sizeof(socket_name.sun_path) - 1);
        socket_initialized = false;
        // Session IDs
        next_session_id = 0;
        sched = new aos_scheduler(num_fpga);
        // TODO: Load some images in

        // Init the FPGA library
        // Only needs to be called once
        int rc = fpga_init();
        if (rc != 0) {
            assert(false);
        }
    }

    // TODO: Implement and call
    void parseImagesJson(std::string fileName) {
        sched->parseImages(fileName);
    }

    void loadDefaultImage(uint64_t fpga_id) {
        assert(fpga_id < num_fpga);
        json default_image = sched->getImageByIdx(0);
        switchImage(fpga_id, default_image);
    }

    int init_socket() {
        if (socket_initialized) {
            printf("Socket already intialied");
        }
        passive_socket = socket(SOCKET_FAMILY, SOCKET_TYPE, 0);
        if (passive_socket == -1) {
           perror("socket");
           exit(EXIT_FAILURE);
        }

        int ret = bind(passive_socket, (const sockaddr *) &socket_name, sizeof( sockaddr_un));
        if (ret == -1) {
           perror("bind");
           exit(EXIT_FAILURE);
        }

        ret = listen(passive_socket, BACKLOG);
        if (ret == -1) {
            perror("listen");
            exit(EXIT_FAILURE);
        }

        socket_initialized = true;
        return 0;
    }

    int writeCommandPacket(int cfd, aos_socket_command_packet & cmd_pckt) {
        if (!socket_initialized) {
            printErrorHost("Can't write command packet without an open socket");
        }
        if (write(cfd, &cmd_pckt, sizeof(aos_socket_command_packet)) == -1) {
            printErrorHost("Daemon socket write error");
        }
        return 0;
    }

    int writeResponsePacket(int cfd, aos_socket_response_packet & resp_pckt) {
        if (!socket_initialized) {
            printErrorHost("Can't write response packet without an open socket");
        }
        if (write(cfd, &resp_pckt, sizeof(aos_socket_response_packet)) == -1) {
            printErrorHost("Daemon socket write response error");
        }
        return 0;
    }

    int readCommandPacket(int cfd, aos_socket_command_packet & cmd_pckt) {
        if (read(cfd, &cmd_pckt, sizeof(aos_socket_command_packet)) == -1) {
            perror("Unable to read from client");
        }
        return 0;
    }

    int readBulkDataFromSocket(int cfd, uint64_t numBytes, char * buf_ptr) {
        if (read(cfd, buf_ptr, numBytes) == -1) {
            perror("Unable to read bulk write packet from client");
        }
        return 0;
    }

    void startTransaction(int & cfd) {
        // blocking call
        cfd = accept(passive_socket, NULL, NULL);
        if (cfd == -1) {
            perror("accept error");
        } 
    }

    void closeTransaction(int cfd) {        
        if (close(cfd) == -1) {
            perror("close error on daemon");
        }
    }

    void listen_loop() {

        aos_socket_command_packet cmd_pckt;
        int cfd;

        std::cout << "AOS Daemon ready to receive requests" << std::endl << std::flush;

        while (1) {

            startTransaction(cfd);

            readCommandPacket(cfd, cmd_pckt);

            //std::cout << "Daemon Received 64 bit value: " <<  cmd_pckt.data64 << " for app " << cmd_pckt.app_id << " for addr " << cmd_pckt.addr64 << std::endl << std::flush;

            handleTransaction(cfd, cmd_pckt);

            closeTransaction(cfd);

            // Later on we can move this to a different thread
            scheduleDMAOperations();

        }

    }

    int handleTransaction(int cfd, aos_socket_command_packet & cmd_pckt) {
        switch(cmd_pckt.command_type) {
            case aos_socket_command::CNTRLREG_WRITE_REQUEST : {
                return handleCntrlRegWriteRequest(cfd, cmd_pckt);
            }
            break;
            case aos_socket_command::CNTRLREG_READ_REQUEST : {
                return handleCntrlReqReadRequest(cfd, cmd_pckt);
            }
            break;
            case aos_socket_command::CNTRLREG_READ_RESPONSE : {
                return handleCntrlRegReadResponse(cfd, cmd_pckt);
            }
            break;
            case aos_socket_command::BULKDATA_WRITE_REQUEST : {
                return handleBulkDataWriteRequest(cfd, cmd_pckt);
            }
            break;
            case aos_socket_command::BULKDATA_READ_REQUEST : {
                return handleBulkDataReadRequest(cfd, cmd_pckt);
            }
            break;
            case aos_socket_command::BULKDATA_READ_RESPONSE : {
                return handleBulkDataReadResponse(cfd, cmd_pckt);
            }
            break;
            case aos_socket_command::INTIATE_SESSION : {
                return handleIntiateSession(cfd, cmd_pckt);
            }
            break;
            case aos_socket_command::END_SESSION : {
                return handleEndSession(cmd_pckt);
            }
            break;
            default: {
                perror("Unimplemented command type in daemon");
            }
            break;
        }
        return 0;
    }

    int handleCntrlRegWriteRequest(int cfd, aos_socket_command_packet & cmd_pckt) {
        const session_id_t session_id = cmd_pckt.session_id;
        int success = 1;

        aos_socket_response_packet resp_pckt;
        resp_pckt.errorcode  = aos_errcode::SUCCESS;
        resp_pckt.session_id = session_id;

        // Check if the session is valid
        if (!isSessionIdValid(session_id)) {
            resp_pckt.errorcode  = aos_errcode::INVALID_SESSION_ID;
            writeResponsePacket(cfd, resp_pckt);
            return success;
        }

        if (!isDummy) {
            if (!isSessionScheduled(session_id)) {
                handleScheduling(session_id);
            }
            const uint64_t fpga_id = getFPGAId(session_id);
            const uint64_t slot_id = getSlotId(session_id);
            success = write_pci_bar1(fpga_id, slot_id, cmd_pckt.addr64, cmd_pckt.data64);
        } else {
            // Dummy mode uses the session_id to access everything, no real slots
            if (dummy_cntrlreg_map.find(session_id) == dummy_cntrlreg_map.end()) {
                dummy_cntrlreg_map[session_id] = std::map<uint64_t, uint64_t>();
            }
            (dummy_cntrlreg_map[session_id])[cmd_pckt.addr64] = cmd_pckt.data64;
            success = 0;
        }

        writeResponsePacket(cfd, resp_pckt);

        return success;
    }

    int handleCntrlReqReadRequest(int cfd, aos_socket_command_packet & cmd_pckt) {
        const session_id_t session_id = cmd_pckt.session_id;
        int success = 1;

        aos_socket_response_packet resp_pckt;
        resp_pckt.errorcode  = aos_errcode::SUCCESS;
        resp_pckt.session_id = session_id;

        // Check if the session is valid
        if (!isSessionIdValid(session_id)) {
            resp_pckt.errorcode  = aos_errcode::INVALID_SESSION_ID;
            writeResponsePacket(cfd, resp_pckt);
            return success;
        }

        uint64_t read_addr_ = cmd_pckt.addr64;

        cntrlRegEnqReadReq(session_id, read_addr_);
        // Check if the read is executed immediately
        if (!isDummy && !lazy_reads) {
            if (!isSessionScheduled(session_id)) {
                handleScheduling(session_id);
            }
            cntrlRegDeqReadReq(session_id);
            uint64_t read_value_;
            const uint64_t fpga_id = getFPGAId(session_id);
            const uint64_t slot_id = getSlotId(session_id);
            success = read_pci_bar1(fpga_id, slot_id, read_addr_, read_value_);
            if (success != 0) {
                perror("Read over pci bar1 failed on the daemon");
                resp_pckt.errorcode = aos_errcode::UNKNOWN_FAILURE;
            }
            cntrlRegEnqReadResp(session_id, read_value_);

        } else {
            if (dummy_cntrlreg_map.find(session_id) == dummy_cntrlreg_map.end()) {
                dummy_cntrlreg_map[session_id] = std::map<uint64_t, uint64_t>();
            }
            auto & app_cntrl_reg_map = dummy_cntrlreg_map[session_id];
            if (app_cntrl_reg_map.find(read_addr_) == app_cntrl_reg_map.end()) {
                app_cntrl_reg_map[read_addr_] = 0x0;
            }
            cntrlRegDeqReadReq(session_id);
            cntrlRegEnqReadResp(session_id, app_cntrl_reg_map[read_addr_]);
            success = 0;
        }

        writeResponsePacket(cfd, resp_pckt);

        return success;
    }

    int handleCntrlRegReadResponse(int cfd, aos_socket_command_packet & cmd_pckt) {
        const session_id_t session_id = cmd_pckt.session_id;
        int success = 0;

        aos_socket_response_packet resp_pckt;
        resp_pckt.errorcode  = aos_errcode::SUCCESS;
        resp_pckt.session_id = session_id;

        if (!lazy_reads && (cntrlreg_read_response_queue[session_id].size() == 0)) {
            perror("No available data to return for the read response");
        }

        uint64_t data64_ = 0x0;

        if (!isDummy) {
            if (!lazy_reads) {
                data64_ = cntrlRegDeqReadResp(session_id);
            } else {
                // Actually execute the read operation
                if (!isSessionScheduled(session_id)) {
                    handleScheduling(session_id);
                }
                uint64_t read_addr_ = cntrlRegDeqReadReq(session_id);
                const uint64_t fpga_id = getFPGAId(session_id);
                const uint64_t slot_id = getSlotId(session_id);
                success = read_pci_bar1(fpga_id, slot_id, read_addr_, data64_);
                if (success != 0) {
                    perror("Read over pci bar1 failed on the daemon");
                    resp_pckt.errorcode = aos_errcode::UNKNOWN_FAILURE;
                }
            }
        } else {
            data64_ = cntrlRegDeqReadResp(session_id);
        }

        resp_pckt.data64    = data64_;

        writeResponsePacket(cfd, resp_pckt);

        return success;
    }

    int handleBulkDataWriteRequest(int cfd, aos_socket_command_packet & cmd_pckt) {
        const session_id_t session_id = cmd_pckt.session_id;

        aos_socket_response_packet resp_pckt;
        memset(&resp_pckt, 0, sizeof(aos_socket_response_packet));

        if (!isSessionIdValid(session_id)) {
            resp_pckt.errorcode = aos_errcode::INVALID_SESSION_ID;
            writeResponsePacket(cfd, resp_pckt);
            return 0;
        }

        aos_app_session * session_ptr = sessions[session_id];

        if (session_ptr->isDMAWriteBufferBusy()) {
            resp_pckt.errorcode = aos_errcode::RETRY;
            writeResponsePacket(cfd, resp_pckt);
            return 0;
        }

        resp_pckt.errorcode = aos_errcode::SUCCESS;
        // Let the client know we're ready to receive the data
        writeResponsePacket(cfd, resp_pckt);

        // Make sure the DMA write buffer for the session is big enough, resize if not
        session_ptr->checkAndResizeMDAWriteBuffer(cmd_pckt.numBytes);
        // Read from the socket into te buffer
        readBulkDataFromSocket(cfd, cmd_pckt.numBytes, session_ptr->getDMAWriteBuffer());
        session_ptr->enqueDMAWrite(cmd_pckt.addr64, cmd_pckt.numBytes, std::time(nullptr));

        pending_dma_session_id.push(session_id);
        pending_dma_operation_type.push(DMA_OPERATION::WRITE);

        return 0;
    }

    int handleBulkDataReadRequest(int cfd, aos_socket_command_packet & cmd_pckt) {
        const session_id_t session_id = cmd_pckt.session_id;

        aos_socket_response_packet resp_pckt;
        memset(&resp_pckt, 0, sizeof(aos_socket_response_packet));

        if (!isSessionIdValid(session_id)) {
            resp_pckt.errorcode = aos_errcode::INVALID_SESSION_ID;
            writeResponsePacket(cfd, resp_pckt);
            return 0;
        }

        aos_app_session * session_ptr = sessions[session_id];

        if (session_ptr->isDMAReadBufferBusy()) {
            resp_pckt.errorcode = aos_errcode::RETRY;
            writeResponsePacket(cfd, resp_pckt);
            return 0;
        }

        resp_pckt.errorcode = aos_errcode::SUCCESS;
        // Let client know we've successfully received the request
        writeResponsePacket(cfd, resp_pckt);
        // Make sure the read buffer for this session is big enough, resize if not
        session_ptr->checkAndResizeDMAReadBuffer(cmd_pckt.numBytes);

        pending_dma_session_id.push(session_id);
        pending_dma_operation_type.push(DMA_OPERATION::READ);

        return 0;
    }

    int handleBulkDataReadResponse(int cfd, aos_socket_command_packet & cmd_pckt) {
        const session_id_t session_id = cmd_pckt.session_id;

        aos_socket_response_packet resp_pckt;
        memset(&resp_pckt, 0, sizeof(aos_socket_response_packet));

        if (!isSessionIdValid(session_id)) {
            resp_pckt.errorcode = aos_errcode::INVALID_SESSION_ID;
            writeResponsePacket(cfd, resp_pckt);
            return 0;
        }

        aos_app_session * session_ptr = sessions[session_id];

        // Check if a read was actually requested
        if (!session_ptr->isDMAReadBufferBusy()) {
            resp_pckt.errorcode = aos_errcode::INVALID_REQUEST;
            writeResponsePacket(cfd, resp_pckt);
        }

        // Let the client know the read is complete and how many bytes it was
        resp_pckt.errorcode = aos_errcode::SUCCESS;
        resp_pckt.numBytes = session_ptr->getDMAReadSize();

        // Send the read results to the client
        if (write(cfd, session_ptr->getDMAReadBuffer(), session_ptr->getDMAReadSize()) == -1) {
            printErrorHost("Daemon socket write error");
        }

        // Clear the DMA read buffer's status
        session_ptr->clearPendingDMARead();

        return 0;
    }

    int handleIntiateSession(int cfd, aos_socket_command_packet & cmd_pckt) {
        std::string app_id(cmd_pckt.char_buf);

        if (!appIdExists(app_id)) {
            perror("App does not exist");
            aos_socket_response_packet resp_pckt;
            resp_pckt.errorcode  = aos_errcode::APP_DOES_NOT_EXIST;
            resp_pckt.data64     = 0;
            resp_pckt.session_id = 0;

            writeResponsePacket(cfd, resp_pckt);
            return 0;
        }

        session_id_t new_session_id = generateNewSessionId();

        sessions[new_session_id] = new aos_app_session(app_id, new_session_id);

        aos_socket_response_packet resp_pckt;
        resp_pckt.errorcode = aos_errcode::SUCCESS;
        resp_pckt.data64     = 0;
        resp_pckt.session_id = new_session_id;

        writeResponsePacket(cfd, resp_pckt);

        return 0;
    }

    int handleEndSession(aos_socket_command_packet & cmd_pckt) {
        const session_id_t session_id = cmd_pckt.session_id;
        // check if the session was valid
        if (!isSessionIdValid(session_id)) {
            // Invalid session
        }

        // Check if the app is bound to a slot and unbind it
        // Also reset the slot if the app was bound
        if (isSessionScheduled(session_id)) {
            const uint64_t fpga_id = getFPGAId(session_id);
            const uint64_t slot_id = getSlotId(session_id);
            unbindAppFromSlot(fpga_id, slot_id);
            resetSlotState(fpga_id, slot_id);
        }

        // Remove the session
        sessions.erase(session_id);

        return 0;
    }

    session_id_t generateNewSessionId() {
        session_id_t tmp = next_session_id;
        next_session_id += 1;
        return tmp;
    }

    int attach_to_image(uint64_t pcie_slot_id) {
        assert(pcie_slot_id < num_fpga);
        assert(!interfaces_enabled[pcie_slot_id]);

        /*
        Only should be called once
        int rc = fpga_init();
        if (rc == 1) {

        }
        */
        check_slot(pcie_slot_id);
        // BAR 1
        attach_pci_bar1(pcie_slot_id);
        // BAR 4
        attach_pci_bar4(pcie_slot_id);
        // XDMA channels
        //attach_xdma_write(pcie_slot_id);
        //attach_xdma_read(pcie_slot_id);

        // Mark interfaces as enabled
        interfaces_enabled[pcie_slot_id] = true;
        return 0;
    }

    int detach_from_image(int fpga_id) {
        assert(interfaces_enabled[fpga_id]);
        // BAR 1
        detach_pci_bar1(fpga_id);
        // BAR 4
        detach_pci_bar4(fpga_id);
        // XDMA Channels
        //detach_xdma_write(fpga_id);
        //detach_xdma_read(fpga_id);

        // Mark interfaces as disabled
        interfaces_enabled[fpga_id] = false;
        return 0;
    }

    int fpga_init() {
        /* initialize the fpga_pci library so we could have access to FPGA PCIe from this applications */
        int rc = fpga_mgmt_init();
        fail_on(rc, out, "Unable to initialize the fpga_mgmt library");
        printf("fpga_mgmt library intialized correctly\n");
        return rc;
        out:
            return 1;
    }

    int check_slot(int slot_id) {
        /* check the afi */
        int rc = check_afi_ready(slot_id);
        fail_on(rc, out, "AFI not ready\n");
        printf("AFI is ready on FPGA %d\n", slot_id);
        return rc;
        out:
            return 1;
    }

    int attach_pci_bar1(int slot_id) {
        // Can't already be attached
        if (bar1_attached[slot_id]) {
            printf("BAR1 already attached");
            assert(false);
        }
        int rc = fpga_pci_attach(slot_id, FPGA_APP_PF, APP_PF_BAR1, 0, &pci_bar1_handle[slot_id]);
        fail_on(rc, out, "Unable to attach to the AFI on slot id %d\n", slot_id);
        printf("Attached to BAR1 on FPGA %d\n", slot_id);
        bar1_attached[slot_id] = true;
        return rc;
        out:
            return 1;
    }

    int attach_pci_bar4(int slot_id) {
        // Can't already be attached
        if (bar4_attached[slot_id]) {
            printf("BAR4 already attached");
            assert(false);
        }
        int rc = fpga_pci_attach(slot_id, FPGA_APP_PF, APP_PF_BAR4, BURST_CAPABLE , &pci_bar4_handle[slot_id]);
        fail_on(rc, out, "Unable to attach to the AFI on slot id %d\n", slot_id);
        printf("Attached to BAR4 on FPGA %d\n", slot_id);
        bar4_attached[slot_id] = true;
        return rc;
        out:
            return 1;
    }

    int attach_xdma_write(uint64_t fpga_id) {
        /* open XDMA write channel */
        int write_fd;
        // Form the channel name
        // TODO: Confirm it's channel id then fpga id and not vice versa
        std::stringstream write_channel_name;
        write_channel_name << "/dev/xdma";
        write_channel_name << 0; // channel zero
        write_channel_name << "_h2c_";
        write_channel_name << fpga_id;
        if ((write_fd = open(write_channel_name.str().c_str(),O_WRONLY)) == -1) {
            write_channel_name << " failed to open";
            perror(write_channel_name.str().c_str());
        }

        xdma_write_channel[fpga_id] = write_fd;
        return 0;        
    }

    int attach_xdma_read(uint64_t fpga_id) {
        /* open XDMA read channel */
        int read_fd;
        // Form the channel name
        // TODO: Confirm it's channel id then fpga id and not vice versa
        std::stringstream read_channel_name;
        read_channel_name << "/dev/xdma";
        read_channel_name << 0; // channel zero
        read_channel_name << "_c2h_";
        read_channel_name << fpga_id;
        if ((read_fd = open(read_channel_name.str().c_str(),O_RDONLY)) == -1) {
            read_channel_name << " failed to open";
            perror(read_channel_name.str().c_str());
        }

        xdma_read_channel[fpga_id] = read_fd;

        return 0;
    }

    int detach_pci_bar1(uint64_t fpga_id) {
        assert(bar1_attached[fpga_id]);
        int rc = fpga_pci_detach(pci_bar1_handle[fpga_id]);
        fail_on(rc, out, "Unable detach pci_bar1 from the FPGA");
        bar1_attached[fpga_id] = false;
        return rc;
        out:
            return 1;
    }

     int detach_pci_bar4(uint64_t fpga_id) {
        assert(bar4_attached[fpga_id]);
        int rc = fpga_pci_detach(pci_bar4_handle[fpga_id]);
        fail_on(rc, out, "Unable detach pci_bar4 from the FPGA");
        bar4_attached[fpga_id] = false;
        return rc;
        out:
            return 1;
    } 

    int detach_xdma_write(uint64_t fpga_id) {
        std::stringstream write_channel_name;
        write_channel_name << "/dev/xdma";
        write_channel_name << 0; // channel zero
        write_channel_name << "_h2c_";
        write_channel_name << fpga_id;
        if (close(xdma_write_channel[fpga_id]) < 0) {
            write_channel_name << " failed to close.";
            perror(write_channel_name.str().c_str());
        }

        xdma_write_channel[fpga_id] = 0;
        return 0;
    }

    int detach_xdma_read(uint64_t fpga_id) {
        std::stringstream read_channel_name;
        read_channel_name << "/dev/xdma";
        read_channel_name << 0; // channel zero
        read_channel_name << "_c2h_";
        read_channel_name << fpga_id;
        if (close(xdma_read_channel[fpga_id]) < 0) {
            read_channel_name << " failed to close.";
            perror(read_channel_name.str().c_str());
        }

        xdma_read_channel[fpga_id] = 0;
        return 0;
    }

    int write_pci_bar1(uint64_t fpga_id, uint64_t slot_id, uint64_t addr, uint64_t value) {
        // Check the address is 64-bit aligned
        if ((addr % 8) != 0) {
            printf("Addr is not correctly aligned");
            assert(false);
        }
        int rc;

        rc = fpga_pci_poke(pci_bar1_handle[fpga_id], applySlotMaskForBAR1(slot_id, addr), lower32(value));
        fail_on(rc, out, "Unable to write first half of BAR1 write");

        rc = fpga_pci_poke(pci_bar1_handle[fpga_id], applySlotMaskForBAR1(slot_id, addr + 0x04), upper32(value));
        fail_on(rc, out, "Unable to write second half of BAR1 write");

        return rc;
        out:
            return 1;
    }

    int read_pci_bar1(uint64_t fpga_id, uint64_t slot_id, uint64_t addr, uint64_t & value) {
        // Check the address is 64-bit aligned
        if ((addr % 8) != 0) {
            printf("Addr is not correctly aligned");
            assert(false);
        }
        int rc;
        uint32_t bottomVal;
        uint32_t upperVal;

        rc = fpga_pci_peek(pci_bar1_handle[fpga_id], applySlotMaskForBAR1(slot_id, addr) , &bottomVal);
        fail_on(rc, out, "Unable to do first read for BAR1");

        rc = fpga_pci_peek(pci_bar1_handle[fpga_id], applySlotMaskForBAR1(slot_id, addr + 0x04) , &upperVal);
        fail_on(rc, out, "Unable to do second read for BAR1");

        // Combine them for the final value
        value = (uint64_t)bottomVal | (((uint64_t)upperVal) << 32);

        return rc;
        out:
            return 1;
    }

private:

    // Scheduler
    aos_scheduler * sched;
    // Num FPGAS
    const uint64_t num_fpga;
    // Image information
    std::vector<bool> interfaces_enabled;
    // All sessions
    session_id_t next_session_id; // make this more secure at some point
    // Map session_id to session object
    std::map<session_id_t, aos_app_session *> sessions;
    // Map slot to session object
    std::vector<std::map<uint64_t, aos_app_session *>> slot_session_map; // should be cleared when an image is switched
    // Map slot to app names
    std::vector<std::map<uint64_t, std::string>> slot_appid_map; // function of the currently loaded image

    // Dummy behavior
    const bool isDummy;
    std::map<uint64_t, std::map<uint64_t, uint64_t>> dummy_cntrlreg_map;

    // CntrlReq read/response state
    const bool lazy_reads;
    std::map<uint64_t, std::queue<uint64_t>> cntrlreg_read_request_queue;
    std::map<uint64_t, std::queue<uint64_t>> cntrlreg_read_response_queue;

    // Keep track of DMA writes/reads that need to happen
    std::queue<uint64_t> pending_dma_session_id;
    std::queue<DMA_OPERATION> pending_dma_operation_type;

    bool areInterfacesEnabled(uint64_t fpga_id) const {
        assert(fpga_id < num_fpga);
        return interfaces_enabled[fpga_id];
    }

    void cntrlRegEnqReadReq(uint64_t app_id, uint64_t read_addr) {
        if (cntrlreg_read_request_queue.find(app_id) == cntrlreg_read_request_queue.end()) {
            cntrlreg_read_request_queue[app_id] = std::queue<uint64_t>();
        }
        cntrlreg_read_request_queue[app_id].push(read_addr);
    }

    uint64_t cntrlRegDeqReadReq(uint64_t app_id) {
        if (cntrlreg_read_request_queue.find(app_id) == cntrlreg_read_request_queue.end()) {
            perror("Invalid app id for cntrl reg read req dequeu");
        }
        uint64_t addr = cntrlreg_read_request_queue[app_id].front();
        cntrlreg_read_request_queue[app_id].pop();
        return addr;
    }

    void cntrlRegEnqReadResp(uint64_t app_id, uint64_t data64) {
        if (cntrlreg_read_response_queue.find(app_id) == cntrlreg_read_response_queue.end()) {
            cntrlreg_read_response_queue[app_id] = std::queue<uint64_t>();
        }
        //std::cout << "Daemon Enqueu resp: " << data64 << " for app: " << app_id << std::endl << std::flush;
        cntrlreg_read_response_queue[app_id].push(data64);
    }

    uint64_t cntrlRegDeqReadResp(uint64_t app_id) {
        if (cntrlreg_read_response_queue.find(app_id) == cntrlreg_read_response_queue.end()) {
            perror("Invalid app id for cntrl reg read resp deque");
        }
        if (cntrlreg_read_response_queue[app_id].size() == 0) {
            perror("No response ready");
        }
        uint64_t data64_ = cntrlreg_read_response_queue[app_id].front();
        //std::cout << "Daemon Deqeue resp: " << data64_ << " for app: " << app_id << std::endl << std::flush;

        cntrlreg_read_response_queue[app_id].pop();
        return data64_;
    }

    // Socket control
    // Create socket
    sockaddr_un socket_name;
    int passive_socket;
    bool socket_initialized;

    // BAR 1
    std::vector<bool> bar1_attached;
    std::vector<pci_bar_handle_t> pci_bar1_handle;

    // BAR 4 for bulk
    std::vector<bool> bar4_attached;
    std::vector<pci_bar_handle_t> pci_bar4_handle;

    // DMA file descriptors
    std::map<uint64_t, int> xdma_write_channel;
    std::map<uint64_t, int> xdma_read_channel;

    // This function will apply the upper bit masks to the address
    uint64_t applySlotMaskForBAR1(uint64_t slot_id, uint64_t addr) {
        return (((slot_id << 13)) | addr) & 0xFFFF;
    }

    int check_afi_ready(int slot_id) {
        struct fpga_mgmt_image_info info = {0}; 
        int rc;

        /* get local image description, contains status, vendor id, and device id. */
        rc = fpga_mgmt_describe_local_image(slot_id, &info,0);
        fail_on(rc, out, "Unable to get AFI information from slot %d. Are you running as root?",slot_id);

        /* check to see if the slot is ready */
        if (info.status != FPGA_STATUS_LOADED) {
            rc = 1;
            fail_on(rc, out, "AFI in Slot %d is not in READY state !", slot_id);
        }

        printf("AFI PCI  Vendor ID: 0x%x, Device ID 0x%x\n",
              info.spec.map[FPGA_APP_PF].vendor_id,
              info.spec.map[FPGA_APP_PF].device_id);

        /* confirm that the AFI that we expect is in fact loaded */
        if (info.spec.map[FPGA_APP_PF].vendor_id != pci_vendor_id || info.spec.map[FPGA_APP_PF].device_id != pci_device_id) {
            printf("AFI does not show expected PCI vendor id and device ID. If the AFI "
                "was just loaded, it might need a rescan. Rescanning now.\n");

            rc = fpga_pci_rescan_slot_app_pfs(slot_id);
            fail_on(rc, out, "Unable to update PF for slot %d",slot_id);
            /* get local image description, contains status, vendor id, and device id. */
            rc = fpga_mgmt_describe_local_image(slot_id, &info,0);
            fail_on(rc, out, "Unable to get AFI information from slot %d",slot_id);

            printf("AFI PCI  Vendor ID: 0x%x, Device ID 0x%x\n", info.spec.map[FPGA_APP_PF].vendor_id, info.spec.map[FPGA_APP_PF].device_id);

            /* confirm that the AFI that we expect is in fact loaded after rescan */
            if (info.spec.map[FPGA_APP_PF].vendor_id != pci_vendor_id || info.spec.map[FPGA_APP_PF].device_id != pci_device_id) {
                rc = 1;
                fail_on(rc, out, "The PCI vendor id and device of the loaded AFI are not "
                    "the expected values.");
            }
        }
        
            return rc;
        out:
            return 1;

    }

    bool isSessionIdValid(session_id_t session_id) {
        return (sessions.count(session_id) == 1);
    }

    bool isSessionScheduled(session_id_t session_id) {
        return sessions[session_id]->boundToSlot();
    }

    uint64_t getFPGAId(session_id_t session_id) {
        return sessions[session_id]->getFPGAId();
    }

    uint64_t getSlotId(session_id_t session_id) {
        return sessions[session_id]->getSlotId();
    }

    /*
    TODO: Implement
    Resets the state of the slot, incase another session had used it prior
    */
    void resetSlotState(uint64_t fpga_id, uint64_t slot_id) {

    }

    /*
    Checks if a slot is available on the current image
    */
    bool slotAvailable(uint64_t fpga_id, std::string app_id)  {
        assert(fpga_id < num_fpga);
        auto & slot_session_map_ = slot_session_map[fpga_id];
        auto & slot_appid_map_   = slot_appid_map[fpga_id];
        const uint64_t total_slots = slot_session_map_.size();
        for (uint64_t slot_id = 0; slot_id < total_slots; slot_id++) {
            if (slot_appid_map_[slot_id] == app_id) {
                return true;
            }
        }
        return false;
    }

    uint64_t getAvailableSlot(uint64_t fpga_id, std::string app_id) {
        assert(fpga_id < num_fpga);
        auto & slot_session_map_ = slot_session_map[fpga_id];
        auto & slot_appid_map_   = slot_appid_map[fpga_id];
        const uint64_t total_slots = slot_session_map_.size();
        for (uint64_t slot_id = 0; slot_id < total_slots; slot_id++) {
            if (slot_appid_map_[slot_id] == app_id) {
                return slot_id;
            }
        }
        return ~0x0;
    }

    // TODO: Implement
    void evacuateApp(uint64_t fpga_id, uint64_t slot_id) {
        // Some state capture
    }

    // TODO: Implement
    void restoreApp(session_id_t session_id, uint64_t fpga_id, uint64_t slot_id) {

    }

    void bindAppToSlot(session_id_t session_id, uint64_t fpga_id, uint64_t slot_id) {
        assert(fpga_id < num_fpga);
        assert(isSessionIdValid(session_id));
        aos_app_session * session_ptr = sessions[session_id];

        slot_session_map[fpga_id][slot_id] = session_ptr;

        session_ptr->bindToSlot(fpga_id, slot_id);

        // Take captured state and put it back on the FPGA (if any)
        if (session_ptr->hasSavedState()) {
            restoreApp(session_id, fpga_id, slot_id);           
        }
    }

    void unbindAppFromSlot(uint64_t fpga_id, uint64_t slot_id) {
        assert(fpga_id < num_fpga);
        aos_app_session * session_ptr = slot_session_map[fpga_id][slot_id];
        if (session_ptr == nullptr) {
            // No App in this slot
            return;
        }
        // Evacuate the app, state capture
        evacuateApp(fpga_id, slot_id);
        // Clean up metadata
        slot_session_map[fpga_id][slot_id] = nullptr;
        session_ptr->unbindFromSlot();
    }

    void unbindAllApps(uint64_t fpga_id) {
        assert(fpga_id < num_fpga);
        auto & slot_session_map_ = slot_session_map[fpga_id];
        const uint64_t num_slots = slot_session_map_.size();
        for (uint64_t slot_id = 0; slot_id < num_slots; slot_id++) {
            unbindAppFromSlot(fpga_id, slot_id);
        }
    }

    void switchImage(uint64_t fpga_id, json & newImage) {
        assert(fpga_id < num_fpga);
        auto & slot_appid_map_   = slot_appid_map[fpga_id];
        auto & slot_session_map_ = slot_session_map[fpga_id];
        // Image specific data
        // Clear the slot_appid_map
        slot_appid_map_.clear();
        // Clear the slot_session_map
        slot_session_map_.clear();

        uint64_t num_slots_new_image = newImage["num_slots"];

        for (uint64_t slot_id = 0; slot_id < num_slots_new_image; slot_id++) {
            slot_session_map_[slot_id] = nullptr; // reset the slot
        }

        slot_appid_map_ = sched->getSlotAppIdMap(newImage);

        assert(slot_appid_map_.size() == slot_session_map_.size());

        // Disable the interfaces to the FPGA
        // Only do it if an image was loaded
        if (areInterfacesEnabled(fpga_id)) {
            detach_from_image(fpga_id);
        }

        // Have the scheduler switch bitstreams
        int32_t image_idx = sched->getImageIdx(newImage);
        assert(image_idx != -1);
        // Clear the old bit stream
        sched->clearImage(fpga_id);
        // Load the new one
        sched->loadImage(fpga_id, (uint32_t)image_idx);

        // Re-enable the interfaces to the FPGA
        attach_to_image(fpga_id);
    }

    json & getReplacementImage(std::string app_id_to_schedule) {

        // Generate app id / count vectors
        std::vector<std::string>   app_ids;
        std::vector<uint32_t>      app_counts;
        // Need the image to have at least one copy of the image we want to schedule
        app_ids.push_back(app_id_to_schedule);
        app_counts.push_back(1);
        // Get all images that can satisfy that have at least one copy of the app we want to ensure is on there
        json app_tuple = sched->generateAppTuples(app_ids, app_counts);
        std::vector<uint32_t> fitting_indices = sched->getAllFittingImages(app_tuple);
        // Determine which image should be the replacement one
        uint32_t selected_idx = 0;
        // Current algorithm just selects the one with the highest overall app/slot count (very basic)
        uint32_t highest_num_apps = 0;
        for (uint32_t vector_idx = 0; vector_idx < fitting_indices.size(); vector_idx++) {
            const uint32_t num_slots = sched->getImageByIdx(fitting_indices[vector_idx])["num_slots"];
            if (num_slots > highest_num_apps) {
                selected_idx = fitting_indices[vector_idx];
                highest_num_apps = num_slots;
            }
        }
        // Return the image corresponding to that index
        std::cout << " Found replacement image, id:" << selected_idx << std::endl;
        std::cout << std::flush;
        return sched->getImageByIdx(selected_idx);
    }

    bool appIdExists(std::string app_id) {
        return sched->appIdExists(app_id);
    }

    // Helper functions
    uint32_t upper32(uint64_t value) {
        return (value >> 32) & 0xFFFFFFFF;
    }

    uint32_t lower32(uint64_t value) {
        return value & 0xFFFFFFFF;
    }

    uint64_t calcFPGALoad(uint64_t fpga_id) {
        assert(fpga_id < num_fpga);
        auto & slot_session_map_ = slot_session_map[fpga_id];
        uint64_t num_slots = slot_session_map_.size();
        uint64_t load = 0;
        for (uint64_t slot_id = 0; slot_id < num_slots; slot_id++) {
            if (slot_session_map_[slot_id] != nullptr) {
                load++;
            }
        }
        return load;
    }

    bool bindAppToUnusedSlot(session_id_t session_id, uint64_t fpga_id) {
        aos_app_session * const session_ptr = sessions[session_id];
        std::string desired_app_id = session_ptr->getAppId();
        auto & slot_session_map_ = slot_session_map[fpga_id];
        auto & slot_appid_map_   = slot_appid_map[fpga_id];
        const uint64_t num_slots = slot_session_map_.size();
        assert(slot_appid_map_.size() == num_slots);
        for (uint64_t slot_id = 0; slot_id < num_slots; slot_id++) {
            // check if the slot can accomidate the app type (app id)
            if (slot_appid_map_[slot_id] == desired_app_id) {
                if (slot_session_map_[slot_id] == nullptr) {
                    // the slot is available
                    bindAppToSlot(session_id, fpga_id, slot_id);
                    // done scheduling
                    return true;
                }
            }
        }
        return false;
    }

    /*
    Check if the current image for a specific FPGA has room for a specific app id
    */
    bool canImageFitAppId(std::string app_id, uint64_t fpga_id, uint64_t & slot_id, bool & slot_empty) {
        assert(false);
        return false;
    }

    /*
    The session_id passed in is not scheduled and needs to be
    */
    bool handleScheduling(session_id_t session_id) {
        assert(isSessionIdValid(session_id));
        assert(!isSessionScheduled(session_id));
        if (isDummy) {
            return true;
        }

        std::cout << std::endl << "================================== Inside handleScheduling , trying to schedule session: " << session_id << std::endl;
        std::cout << std::flush;
        dumpSchedulerState();

        aos_app_session * const session_ptr = sessions[session_id];
        std::string desired_app_id = session_ptr->getAppId();

        // Steps to schedule this app
        /*
        1) Find an empty FPGA that preferably has no image or all slots unbound (no running apps/load == 0)
        2) Find an empty slot on any currently flashed FPGA that can accomidate this app
            a) If tie, use the FPGA with the lesser load on it
        3) Find all flashed FPGAs and all slots on those FPGAs that can fit this app
            a) If tie either pick global LRU or FPGA with least/most load
        4) If no FPGA can fit this app, then we need to select an FPGA for image replacement
        */

        bool empty_fpga_found = false;
        uint64_t fpga_id_to_use = ~0x0;

        // 1) Find an empty FPGA or an FPGA with all slots unbound
        for (uint64_t fpga_id = 0; fpga_id < num_fpga; fpga_id++) {
            if (!sched->anyImageLoaded(fpga_id)) {
                empty_fpga_found = true;
                fpga_id_to_use   = fpga_id;
                break;
            }
        }
        if (!empty_fpga_found) {
            for (uint64_t fpga_id = 0; fpga_id < num_fpga; fpga_id++) {
                if (calcFPGALoad(fpga_id) == 0) {
                    empty_fpga_found = true;
                    fpga_id_to_use   = fpga_id;
                    break;
                }
            }
        }

        if (empty_fpga_found) {
        	std::cout << "Empty FPGA found, fpga id: " << fpga_id_to_use << " ,trying to schedule app: " << desired_app_id << std::endl;
        	std::cout << std::flush;
            auto & newImage = getReplacementImage(desired_app_id);
            switchImage(fpga_id_to_use, newImage);
            //return true;
        }

        // 2 & 3) No Empty FPGA was found or we just loaded the image we needed!
        uint64_t max_load = ~0x0;
        bool matching_slot_found = false;
        bool matching_empty_slot_found = false;
        uint64_t slot_id_to_use = ~0x0;
        fpga_id_to_use = ~0x0;

        for (uint64_t fpga_id = 0; fpga_id < num_fpga; fpga_id++) {
            const uint64_t fpga_load = calcFPGALoad(fpga_id);
            auto & slot_appid_map_ = slot_appid_map[fpga_id];
            auto & slot_session_map_ = slot_session_map[fpga_id];
            const uint64_t num_slots = slot_session_map_.size();
            // First see if we can find a slot that both app id matches and is empty
            for (uint64_t slot_id = 0; slot_id < num_slots; slot_id++) {
                if (slot_appid_map_[slot_id] == desired_app_id) {
                    // See if the matching slot is also empty
                    if (slot_session_map_[slot_id] == nullptr) {
                        // Found an empty slot
                        if (!matching_empty_slot_found) {
                            // First empty slot found
                            max_load = fpga_load;
                            matching_slot_found = true;
                            matching_empty_slot_found = true;
                            slot_id_to_use = slot_id;
                            fpga_id_to_use = fpga_id;
                            break; // Not interested in additional slots on this FPGA
                        } else {
                            // Another matching empty slot was found prior
                            // Use load as a tie breaker
                            if (max_load > fpga_load) {
                                // this one wins out
                                max_load = fpga_load;
                                slot_id_to_use = slot_id;
                                fpga_id_to_use = fpga_id;
                                break; // Not interested in additional slots on this FPGA
                            }
                        }
                    } else {
                        // First slot found with a match across all FPGAs
                        if (!matching_slot_found) {
                            max_load = fpga_load;
                            matching_slot_found = true;
                            slot_id_to_use = slot_id;
                            fpga_id_to_use = fpga_id;
                            continue; // Keep going through other slots, because they might be empty
                        } else if (matching_slot_found && !matching_empty_slot_found) {
                            // A prior non-empty slot was found, use load as tie break
                            if (max_load > fpga_load) {
                                max_load = fpga_load;
                                slot_id_to_use = slot_id;
                                fpga_id_to_use = fpga_id;
                                break; // Not interested in additional slots on this FPGA
                            }
                        }
                    }
                } // Appid == desired app id
            } // slot loop
        } // fpga loop

        if (matching_empty_slot_found) {
        	std::cout << "Matching slot found, binding app to the slot " << slot_id_to_use << " on FPGA ID: " << fpga_id_to_use << std::endl;
        	std::cout << std::flush;
            bindAppToSlot(session_id, fpga_id_to_use, slot_id_to_use);
            return true;
        } else if (matching_slot_found) {
        	std::cout << "No matching slot found! Need to unbind an app" << std::endl;
        	std::cout << std::flush;
            // swap out the old session
            unbindAppFromSlot(fpga_id_to_use, slot_id_to_use);
            // Reset the app slot on the FPGA
            resetSlotState(fpga_id_to_use, slot_id_to_use);
            // swap in the new session
            bindAppToSlot(session_id, fpga_id_to_use, slot_id_to_use);
            // done scheduling
            return true;        
        }

        // 4) No FPGA can accomidate the app_id, and we need to flash a new image onto one
        std::cout << "No matching FPGA slot found, looking for replacement" << std::endl;
        std::cout << std::flush;

        uint64_t victim_fpga_id = ~0x0;
        max_load = ~0x0;

        // Compute the load of all FPGAs
        for (uint64_t fpga_id = 0; fpga_id < num_fpga; fpga_id++) {
            const uint64_t fpga_load = calcFPGALoad(fpga_id);
            if (fpga_load < max_load) {
                victim_fpga_id = fpga_id;
            }
        }

        // Unbind and evacuate every app on the image
        unbindAllApps(victim_fpga_id);
        // Select replacement image
        auto & newImage = getReplacementImage(desired_app_id);
        // Change images
        // Do not have to call resetSlotState because flashing a new image issues a reset
        switchImage(victim_fpga_id, newImage);
        // Schedule the app
        const uint64_t new_num_slots = slot_session_map[victim_fpga_id].size();
        assert(slot_appid_map[victim_fpga_id].size() == new_num_slots);
        for (uint64_t slot_id = 0; slot_id < new_num_slots; slot_id++) {
            // check if the slot can accomidate the app type (app id)
            if (slot_appid_map[victim_fpga_id][slot_id] == desired_app_id) {
                if (slot_session_map[victim_fpga_id][slot_id] == nullptr) {
                    // the slot is available
                    bindAppToSlot(session_id, victim_fpga_id, slot_id);
                    // done scheduling
                    return true;
                }
                // Shouldn't find a fitting slot AND it be NOT available since we
                // just swapped in a new image
            }
        }

        // Scheduling failed
        return false;
        /*

        bool any_appid_match_found = false;
        uint64_t slot_id_of_lru = 0xFFFFFFFF;
        std::time_t lru_access_time = std::time(nullptr); // current time

        const uint64_t num_slots = slot_session_map.size();
        assert(slot_appid_map.size() == num_slots);
        for (uint64_t slot_id = 0; slot_id < num_slots; slot_id++) {
            // check if the slot can accomidate the app type (app id)
            if (slot_appid_map[slot_id] == desired_app_id) {
                any_appid_match_found = true;
                // check if anything is scheduled in this slot
                // use the first slot we find
                if (slot_session_map[slot_id] == nullptr) {
                    // the slot is available
                    bindAppToSlot(session_id, slot_id);
                    // done scheduling
                    return true;
                } else {
                    // Search for the LRU
                    std::time_t slot_last_access_time = slot_session_map[slot_id]->getLastAccessTime();
                    if (slot_last_access_time < lru_access_time) {
                        slot_id_of_lru = slot_id;
                        lru_access_time = slot_last_access_time;
                    }
                }
            }
        }

        */
    }

    void scheduleDMAOperations() {

    }
  
    void dumpSchedulerState() {
        // Print all Active sessions
        cout << "Scheduler State: " << endl;
        cout << "Num sessions: " << sessions.size() << endl;
        for (auto const & session_pair : sessions) {
            cout << "ID: "
                 << session_pair.first
                 << " "
                 << (session_pair.second)->debugString()
                 << std::endl;
        }        
        // For each FPGA
        for (uint64_t fpga_id = 0; fpga_id < num_fpga; fpga_id++) {
            cout << "FPGA ID: " << fpga_id << std::endl;
            // Print each slot
            const uint64_t num_slots = slot_session_map[fpga_id].size();
            assert(slot_appid_map[fpga_id].size() == num_slots);
            for (uint64_t slot_id = 0; slot_id < num_slots; slot_id++) {
                cout << "Slot: "
                     << slot_id
                     << " AppId: "
                     << slot_appid_map[fpga_id][slot_id]
                     << " SessionId: "
                     << ((slot_session_map[fpga_id][slot_id] == nullptr ? 0xDEADDEADDEADDEAD : (slot_session_map[fpga_id][slot_id]->getSessionId())))
                     << std::endl;
            }
        }

        cout << std::flush;

    }

};
