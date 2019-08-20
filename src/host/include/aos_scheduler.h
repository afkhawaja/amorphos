#include "aos_host_common.h"

class aos_scheduler {
public:

    aos_scheduler(uint64_t num_fpgas);
    void parseImages(std::string fileName);

    bool agfiExists(std::string agfi);
    bool anyImageLoaded(uint64_t fpga_id);
    json getImageByAgfi(std::string agfi);
    json & getImageByIdx(uint32_t image_idx);

    json generateAppTuples(std::vector<std::string> app_ids, std::vector<uint32_t> app_counts);

    std::vector<uint32_t> getAllFittingImages(json & app_tuples);

    bool canImageSatisfyNeed(json & image, json & app_ids);
    json convertImageToAppTuples(json & image);

    int32_t getFittingImageIdx(json & app_ids);
    int32_t getImageIdx(json & image);

    bool appIdExists(std::string app_id);

    std::map<uint64_t, std::string> getSlotAppIdMap(json & image);

    // Run on the FPGA
    void clearImage(uint64_t fpga_id);
    void loadImage(uint64_t fpga_id, uint32_t image_idx);

private:

    const uint64_t num_fpga;
    json image_library;
    std::vector<json> current_image;

};
