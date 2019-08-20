#include "aos_host_common.h"
#include "aos_scheduler.h"

int main(void) {

    uint64_t num_fpga = 1;
    uint64_t fpga_id0 = 0;

    aos_scheduler sched(num_fpga);

    sched.parseImages("/home/centos/src/project_data/amorphos-design/f1_host/fpga_images.json");

    assert(sched.appIdExists("dnn_weaver_v0"));
    assert(sched.appIdExists("memdrive_v0"));
    assert(!sched.appIdExists("dummy_app_id"));

    std::string dnn8_agfi = "agfi-0b2652bbc7b28bb43";
    std::string memdrive1_agfi = "agfi-0c0657b6083fac971";

    assert(sched.agfiExists(dnn8_agfi));
    assert(sched.agfiExists(memdrive1_agfi));
    assert(!sched.agfiExists("Something-Fake"));

    assert(!sched.anyImageLoaded(fpga_id0));

    json image0 = sched.getImageByAgfi(dnn8_agfi);

    assert(image0["agfi"] == dnn8_agfi);

    std::cout << image0 << std::endl;

    json & image00 = sched.getImageByIdx(0);

    assert(sched.getImageIdx(image00) == 0);

    assert(image00["agfi"] == dnn8_agfi);

    std::vector<std::string> app_ids;
    std::vector<uint32_t> app_counts;

    app_ids.push_back("dnn_weaver_v0");
    app_counts.push_back(8);

    json app_tuple0 = sched.generateAppTuples(app_ids, app_counts);

    std::cout << app_tuple0 << std::endl;

    assert(sched.getFittingImageIdx(app_tuple0) == 0);

    std::vector<uint32_t> fitting_image_idxs = sched.getAllFittingImages(app_tuple0);

    assert(sched.canImageSatisfyNeed(image00, app_tuple0));

    std::cout << "Fitting indices: ";
    for (auto & idx : fitting_image_idxs) {
        std::cout << idx << " ";
    }
    std::cout << std::endl;

    std::vector<std::string> app_ids1;
    std::vector<uint32_t> app_counts1;

    app_ids1.push_back("memdrive_v0");
    app_counts1.push_back(1);

    json app_tuple1 = sched.generateAppTuples(app_ids1, app_counts1);

    assert(!sched.canImageSatisfyNeed(image00, app_tuple1));

    assert(sched.getAllFittingImages(app_tuple1).size() == 1);

    std::vector<std::string> app_ids2;
    std::vector<uint32_t> app_counts2;

    app_ids2.push_back("memdrive_v0");
    app_counts2.push_back(16);

    json app_tuple2 = sched.generateAppTuples(app_ids2, app_counts2);

    assert(!sched.canImageSatisfyNeed(image00, app_tuple2));

    assert(sched.getAllFittingImages(app_tuple2).size() == 0);

    json app_tuple3 = sched.convertImageToAppTuples(image0);

    std::cout << app_tuple3 << std::endl;

    // Slot ID map
    std::map<uint64_t, std::string> slotIdMap0 = sched.getSlotAppIdMap(image0);

    std::cout << "Slot ID Map:" << std::endl;
    for (uint64_t i = 0; i < slotIdMap0.size(); i++) {
        std::cout << "Slot " << i << " " << slotIdMap0[i] << std::endl;
    }

    std::map<uint64_t, std::string> slotIdMap1 = sched.getSlotAppIdMap(sched.getImageByIdx(sched.getFittingImageIdx(app_tuple1)));

    std::cout << "Slot ID Map:" << std::endl;
    for (uint64_t i = 0; i < slotIdMap1.size(); i++) {
        std::cout << "Slot " << i << " " << slotIdMap1[i] << std::endl;
    }

    sched.clearImage(fpga_id0);

    sleep(2);

    sched.loadImage(fpga_id0, 0);

    sleep(2);

    sched.clearImage(fpga_id0);

    sleep(2);
    
    sched.loadImage(fpga_id0, 1);
    
    sleep(2);
    
    sched.loadImage(fpga_id0, 0);
    
    return 0;

}