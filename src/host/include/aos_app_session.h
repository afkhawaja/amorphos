#include "aos_host_common.h"

#define DMA_BUFFER_ALIGNMENT 512
#define DEFAULT_DMA_WRITE_BUF_SIZE 1024*1024
#define DEFAULT_DMA_READ_BUF_SIZE  1024*1024

class aos_host;

class aos_app_session {
public:

    friend class ::aos_host;
    aos_app_session(std::string app_id, session_id_t session_id);
    ~aos_app_session();
    void unbindFromSlot();
    void bindToSlot(uint64_t fpga_id, uint64_t slot_id);
    bool boundToSlot() const;
    uint64_t getFPGAId() const;
    uint64_t getSlotId() const;
    std::string getAppId() const;
    bool hasSavedState() const;
    std::string debugString() const;
    session_id_t getSessionId() const;
    void updateLastAccessTime();
    std::time_t getCreationTime() const;
    std::time_t getLastAccessTime() const;
    bool isMoreRecentlyUsed(aos_app_session * other) const;
    bool isDMAWriteBufferBusy() const;
    bool isDMAReadBufferBusy() const;
    char * getDMAWriteBuffer();
    char * getDMAReadBuffer();
    void checkAndResizeMDAWriteBuffer(uint64_t numBytes);
    void checkAndResizeDMAReadBuffer(uint64_t numBytes);
    void enqueDMAWrite(uint64_t addr, uint64_t numBytes, std::time_t requestTime);
    void enqueDMARead(uint64_t addr, uint64_t numBytes, std::time_t requestTime);
    void clearPendingDMAWrite();
    void clearPendingDMARead();
    std::time_t getDMAWriteTime() const;
    std::time_t getDMAReadTime() const;
    uint64_t getDMAWriteAddr() const;
    uint64_t getDMAReadAddr() const;
    bool isDMAWriteComplete() const;
    bool isDMAReadComplete() const;
    void markDMAWriteComplete();
    void markDMAReadComplete();
    uint64_t getDMAReadSize() const;

private:

    std::string app_id;
    session_id_t session_id;
    bool active_slot;
    uint64_t fpga_id;
    uint64_t fpga_slot;
    bool saved_state;
    std::time_t creation_time;
    std::time_t last_access_time;
    // DMA Support
    // Writes
    char * dma_write_buffer;
    uint64_t dma_write_buffer_size;
    bool dma_write_buffer_busy;
    uint64_t dma_write_valid_bytes;
    uint64_t dma_write_dest_addr;
    std::time_t dma_write_enque_time;
    bool dma_write_complete;
    // Reads
    char * dma_read_buffer;
    uint64_t dma_read_buffer_size;
    bool dma_read_buffer_busy;
    uint64_t dma_read_valid_bytes;
    uint64_t dma_read_dest_addr;
    std::time_t dma_read_enque_time;
    bool dma_read_complete;

};