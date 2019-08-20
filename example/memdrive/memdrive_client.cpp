#include "aos.h"

int main(int argc, char **argv) {

    const uint64_t num_instances = 8;

    aos_client * client_handle[num_instances];
    uint64_t session_id[num_instances];

    for (uint64_t i = 0; i < num_instances; i++) {
        client_handle[i] = new aos_client("memdrive_v0");
        if (client_handle[i]->aos_init_session() != aos_errcode::SUCCESS) {
            printf("Memdrive app %ld unable to get a session id\n", i);
            return -1;
        } else {
            session_id[i] = client_handle[i]->getSessionId();
            printf("Memdrive app %ld established session with session id %ld \n", i, session_id[i]);
        }
    }

    // Program Mem Drive
    uint64_t start_addr0 = 0x0;
    uint64_t total_subs  = 0x15;
    uint64_t mask = 0xFFFFFFFFFFFFFFFF;
    uint64_t mode = 0x1; // write == 1, read = 0
    uint64_t start_addr1 = 0xC000;
    uint64_t addr_delta  = 6;
    uint64_t canary0     = 0xFEEBFEEBBEEFBEEF;
    uint64_t canary1     = 0xDAEDDAEDDEADDEAD;

    for (uint64_t i = 0; i < num_instances; i++) {
        client_handle[i]->aos_cntrlreg_write(0x00, start_addr0);
        client_handle[i]->aos_cntrlreg_write(0x08, total_subs);
        client_handle[i]->aos_cntrlreg_write(0x10, mask);
        client_handle[i]->aos_cntrlreg_write(0x18, mode);
        client_handle[i]->aos_cntrlreg_write(0x20, start_addr1);
        client_handle[i]->aos_cntrlreg_write(0x28, addr_delta);
        client_handle[i]->aos_cntrlreg_write(0x30, canary0);
        client_handle[i]->aos_cntrlreg_write(0x38, canary1);
    }

    // Read back runtime
    uint64_t start_cycle;
    uint64_t end_cycle;

    for (uint64_t i = 0; i < num_instances; i++) {
        client_handle[i]->aos_cntrlreg_read(0x00ULL, start_cycle);
        client_handle[i]->aos_cntrlreg_read(0x08ULL, end_cycle);

        printf("Memdrive app %ld start cycle: %ld\n", i, start_cycle);
        printf("Memdrive app %ld end cycle: %ld\n", i, end_cycle);
        printf("Memdrive app %ld runtime: %ld\n"  , i, (end_cycle - start_cycle));

    }

    for (uint64_t i = 0; i < num_instances; i++) {
        client_handle[i]->aos_end_session();
    }

    printf("========= MemDrive Successfully Run =========");

    return 0;

}
