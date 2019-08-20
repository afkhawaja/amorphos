#include "aos_scheduler.h"

aos_scheduler::aos_scheduler(uint64_t num_fpgas):
    num_fpga(num_fpgas),
    current_image(num_fpga)
{
    for (uint64_t fpga_id = 0; fpga_id < num_fpga; fpga_id++) {
        current_image[fpga_id] = json();
    }
}

void aos_scheduler::parseImages(std::string fileName) {

    std::ifstream json_in_file;
    json_in_file.open(fileName);

    json parsed_file = json::parse(json_in_file);

    json_in_file.close();

    if (image_library.empty()) {
        cout << "Scheduler: Image Library is initially empty" << endl << flush;
    }

    cout << "Scheduler: Parsed file " << fileName << " and found " << parsed_file["images"].size() << " images." << endl << flush;

    for (auto & image : parsed_file["images"]) {
        std::string agfi_ = image["agfi"];
        if (agfiExists(agfi_)) {
            cout << "Scheduler: Skipping already exists agfi: " << agfi_ << endl << flush;
        } else {
            image_library.push_back(image);
            cout << "Scheduler: Image Library Adding agfi: " << agfi_ << " Description: " << image["description"] << endl << flush;
        }
    } // for in

    cout << "Scheduler: Image library now has " << image_library.size() << " images." << endl << flush;
}

void aos_scheduler::clearImage(uint64_t fpga_id) {
    assert(fpga_id < num_fpga);
    cout << "Scheduler: Preparing to clear FPGA Image on FPGA " << fpga_id << endl << flush;
    std::stringstream clear_command;
    clear_command << "sudo fpga-clear-local-image  -S ";
    clear_command << fpga_id;
    std::string clear_result = cmd_exec(clear_command.str());
    cout << "Scheduler: Clear result: " << clear_result << endl << flush;
    current_image[fpga_id].clear();
}

void aos_scheduler::loadImage(uint64_t fpga_id, uint32_t image_idx) {
    assert(fpga_id < num_fpga);

    if (image_idx > image_library.size()) {
        cout << "Scheduler: Invalid image selection index." << endl << flush;
        return;
    }

    if (anyImageLoaded(fpga_id)) {
        cout << "Scheduler: On FPGA " << fpga_id << " Overwritting current image agfi: " << current_image[fpga_id]["agfi"] << " Description: " << current_image[fpga_id]["description"] << endl << flush;
    } else {
        cout << "Scheduler: On FPGA " << fpga_id << " No prior image written" << endl << flush;
    }

    std::string afgi = image_library[image_idx]["agfi"];
    std::string image_desc = image_library[image_idx]["description"];
    std::stringstream load_cmd; 
    load_cmd << "sudo fpga-load-local-image -S ";
    load_cmd << fpga_id;
    load_cmd << " -I ";
    load_cmd << afgi;

    cout << "Scheduler: On FPGA " << fpga_id << " Attempting to load image with index " << image_idx << " afgi: " << afgi << " Description: " << image_desc << endl << flush;

    std::string load_result = cmd_exec(load_cmd.str());

    cout << "Scheduler: On FPGA " << fpga_id << " Load result: " << load_result << endl << flush;

    current_image[fpga_id] = image_library[image_idx];

}

bool aos_scheduler::agfiExists(std::string agfi) {

    for (auto & image : image_library) {
        std::string agfi_ = image["agfi"];
        if (agfi == agfi_) {
            return true;
        }
    }

    return false;
}

bool aos_scheduler::anyImageLoaded(uint64_t fpga_id) {
    assert(fpga_id < num_fpga);
    if (current_image[fpga_id].size() == 0) {
        return false;
    } else {
        return true;
    }
}


json aos_scheduler::getImageByAgfi(std::string agfi) {
    for (auto & image : image_library) {
        std::string agfi_ = image["agfi"];
        if (agfi == agfi_) {
            return image;
        }
    }

    return json();
}

json & aos_scheduler::getImageByIdx(uint32_t image_idx) {
    assert(image_idx < image_library.size());
    return image_library[image_idx];
}

/*
    App Tuple Format:

    {
        "app_id_0" : {
            "count" : 1
        },
        "app_id_1": {
            "count": 2
        }
    }

*/
bool aos_scheduler::canImageSatisfyNeed(json & image, json & app_tuples) {

    json image_as_tuple = convertImageToAppTuples(image);

    for (auto & app_id : app_tuples.items()) {
        // Check if the image has the type of app we want
        if (image_as_tuple.find(app_id.key()) == image_as_tuple.end()) {
            return false;
        }
        // Now check if it has enough of them
        if (image_as_tuple[app_id.key()]["count"] < app_id.value()["count"]) {
            return false;
        }
    } 

    // All checks have passed
    return true;
}

/*
Returns the index of the image that can satisfy all apps we would like
to run concurrently, -1 otherwise
*/
int32_t aos_scheduler::getFittingImageIdx(json & app_ids) {

    int index = 0;
    for (auto & image : image_library) {
        if (canImageSatisfyNeed(image , app_ids)) {
            return index;
        }
        index++;
    }

    return -1;
}


std::vector<uint32_t> aos_scheduler::getAllFittingImages(json & app_tuples) {
    std::vector<uint32_t> indices;
    uint32_t index = 0;
    for (auto & image : image_library) {
        if (canImageSatisfyNeed(image , app_tuples)) {
            indices.push_back(index);
        }
        index++;
    }
    return indices;
}

/*
    Given an image, get it's index in the image library
*/
int32_t aos_scheduler::getImageIdx(json & image) {
    std::string agfi = image["agfi"];

    int index = 0;
    for (auto & image_ : image_library) {
        std::string check_agfi = image_["agfi"];
        if (agfi == check_agfi) {
            return index;
        }
        index++;
    }

    return -1;
}

/*
    Converts an Image into the App Tuple Format

*/
json aos_scheduler::convertImageToAppTuples(json & image) {
    json app_tuples;
    for (auto & slot : image["slots"]) {
        std::string app_id = slot["app_id"];
        if (app_tuples.find(app_id) != app_tuples.end()) {
            // update count of existing app_id
            uint32_t current_count = app_tuples[app_id]["count"];
            app_tuples[app_id]["count"] = (current_count + 1);
        } else {
            // adding new entry
            app_tuples[app_id]["count"]  = 1;
            //app_tuples[app_id]["app_id"] = std::string(); // replicated
        }
    }
    return app_tuples;
}

std::map<uint64_t, std::string> aos_scheduler::getSlotAppIdMap(json & image) {

    std::map<uint64_t, std::string> slot_appid_map;

    for (auto & slot : image["slots"]) {
        uint64_t slot_id = slot["slot_id"];
        std::string app_id = slot["app_id"];
        slot_appid_map[slot_id] = app_id;
    }

    return slot_appid_map;

}

/*
    Does the app exist in any image?

*/
bool aos_scheduler::appIdExists(std::string app_id) {
    json app_tuple;
    app_tuple[app_id]["count"] = 1;
    if (getFittingImageIdx(app_tuple) == -1) {
        return false;
    } else {
        return true;
    }
}

json aos_scheduler::generateAppTuples(std::vector<std::string> app_ids, std::vector<uint32_t> app_counts) {
    json app_tuples;
    int idx = 0;
    for (auto & app_id_ : app_ids) {
        app_tuples[app_id_]["count"] = app_counts[idx];
        idx++;
    }
    return app_tuples;
}
