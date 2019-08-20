#include "aos_app_session.h"

aos_app_session::aos_app_session(std::string app_id, session_id_t session_id): 
    app_id(app_id),
    session_id(session_id),
    active_slot(false),
    fpga_id(~0x0),
    fpga_slot(~0x0),
    saved_state(false),
    creation_time(std::time(nullptr)),
    last_access_time(creation_time)
{
    // Setup DMA Buffwers
    // Write Buffer
    dma_write_buffer = (char *)aligned_alloc(DMA_BUFFER_ALIGNMENT, DEFAULT_DMA_WRITE_BUF_SIZE);
    dma_write_buffer_size = DEFAULT_DMA_WRITE_BUF_SIZE;
    dma_write_buffer_busy = false;
    dma_write_valid_bytes = 0;
    dma_write_dest_addr = 0;
    dma_write_enque_time = 0;
    dma_write_complete = false;

    dma_read_buffer = (char *)aligned_alloc(DMA_BUFFER_ALIGNMENT, DEFAULT_DMA_READ_BUF_SIZE);
    dma_read_buffer_size = DEFAULT_DMA_READ_BUF_SIZE;
    dma_read_buffer_busy = false;
    dma_read_valid_bytes = 0;
    dma_read_dest_addr = 0;
    dma_read_enque_time = 0;
    dma_read_complete = false;
}

aos_app_session::~aos_app_session() {
    if (dma_write_buffer != nullptr) {
        free(dma_write_buffer);
        dma_write_buffer = nullptr;
    }
    if (dma_read_buffer != nullptr) {
        free(dma_read_buffer);
        dma_read_buffer = nullptr;
    }
}

void aos_app_session::unbindFromSlot() {
    active_slot = false;
    fpga_id     = (~0x0);
    fpga_slot   = (~0x0);
}

void aos_app_session::bindToSlot(uint64_t fpga_num_id, uint64_t slot_id) {
    active_slot = true;
    fpga_id     = fpga_num_id; 
    fpga_slot   = slot_id;
}

bool aos_app_session::boundToSlot() const {
    return active_slot;
}

uint64_t aos_app_session::getFPGAId() const {
    return fpga_id;
}

uint64_t aos_app_session::getSlotId() const {
    return fpga_slot;
}

std::string aos_app_session::getAppId() const {
    return app_id;
}

bool aos_app_session::hasSavedState() const {
    return saved_state;
}

std::string aos_app_session::debugString() const {
    std::string toRet = "SID: ";
    toRet += session_id;
    toRet += " AppId: ";
    toRet += app_id;
    toRet += " Scheduled: ";
    toRet += (active_slot ? " Yes" : " No");
    toRet += " FPGA ID: ";
    toRet += fpga_id;
    toRet += " Slot: ";
    if (active_slot) {
        toRet += fpga_slot;
    } else {
        toRet += "NONE";
    }
    toRet += (saved_state ? " Yes" : " No");
    return toRet;
}

session_id_t aos_app_session::getSessionId() const {
    return session_id;
}

void aos_app_session::updateLastAccessTime() {
    last_access_time = std::time(nullptr);
}

std::time_t aos_app_session::getCreationTime() const {
    return creation_time;
}

std::time_t aos_app_session::getLastAccessTime() const {
    return last_access_time;
}

bool aos_app_session::isMoreRecentlyUsed(aos_app_session * other) const {
    return (last_access_time > other->getLastAccessTime());
}

bool aos_app_session::isDMAWriteBufferBusy() const {
    return dma_write_buffer_busy;
}

bool aos_app_session::isDMAReadBufferBusy() const {
    return dma_read_buffer_busy;
}

char * aos_app_session::getDMAWriteBuffer() {
    return dma_write_buffer;
}

char * aos_app_session::getDMAReadBuffer() {
    return dma_read_buffer;
}

void aos_app_session::checkAndResizeMDAWriteBuffer(uint64_t numBytes) {
    assert(!dma_write_buffer_busy);

    // Current buffer is adequately sized
    if (numBytes < dma_write_buffer_size) {
        return;
    }
    // Allocate a larger buffer
    free(dma_write_buffer);
    // Find the next largest power of 2
    uint64_t new_buf_size = pow(2, ceil(log(numBytes)/log(2)));

    dma_write_buffer = (char *)aligned_alloc(DMA_BUFFER_ALIGNMENT, new_buf_size);
    dma_write_buffer_size = new_buf_size;
    dma_write_valid_bytes = 0;
}

void aos_app_session::checkAndResizeDMAReadBuffer(uint64_t numBytes) {
    assert(!dma_read_buffer_busy);

    // Current buffer is adequately sized
    if (numBytes < dma_read_buffer_size) {
        return;
    }
    // Allocate a larger buffer
    free(dma_read_buffer);
    // Find the next largest power of 2
    uint64_t new_buf_size = pow(2, ceil(log(numBytes)/log(2)));

    dma_read_buffer = (char *)aligned_alloc(DMA_BUFFER_ALIGNMENT, new_buf_size);
    dma_read_buffer_size = new_buf_size;
    dma_read_valid_bytes = 0;
}

void aos_app_session::enqueDMAWrite(uint64_t addr, uint64_t numBytes, std::time_t requestTime) {
    dma_write_valid_bytes = numBytes;
    dma_write_dest_addr   = addr;
    dma_write_enque_time  = requestTime;
    dma_write_buffer_busy = true;
}

void aos_app_session::enqueDMARead(uint64_t addr, uint64_t numBytes, std::time_t requestTime) {
    dma_read_valid_bytes  = numBytes;
    dma_read_dest_addr    = addr;
    dma_read_enque_time   = requestTime;
    dma_read_buffer_busy  = true;
}

void aos_app_session::clearPendingDMAWrite() {
    dma_write_valid_bytes = 0;
    dma_write_dest_addr   = 0;
    dma_write_enque_time  = 0;
    dma_write_complete    = false;
}

void aos_app_session::clearPendingDMARead() {
    dma_read_valid_bytes  = 0;
    dma_read_dest_addr    = 0;
    dma_read_enque_time   = 0;
    dma_read_complete     = false;
}

std::time_t aos_app_session::getDMAWriteTime() const {
    return dma_write_enque_time;
}

std::time_t aos_app_session::getDMAReadTime() const {
    return dma_read_enque_time;
}

uint64_t aos_app_session::getDMAWriteAddr() const {
    return dma_write_dest_addr;
}

uint64_t aos_app_session::getDMAReadAddr() const {
    return dma_read_dest_addr;
}

bool aos_app_session::isDMAWriteComplete() const {
    return dma_write_complete;
}

bool aos_app_session::isDMAReadComplete() const {
    return dma_read_complete;
}

void aos_app_session::markDMAWriteComplete() {
  dma_write_complete = true;
}

void aos_app_session::markDMAReadComplete() {
  dma_read_complete = true;
}

uint64_t aos_app_session::getDMAReadSize() const {
  return dma_read_valid_bytes;
}

