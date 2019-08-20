#include "json.hpp"
#include <iostream>
#include <fstream>
#include <cstdio>
#include <memory>
#include <stdexcept>
#include <string>
#include <array>

using namespace std;


using json = nlohmann::json;

std::string cmd_exec(const char* cmd) {
    std::array<char, 128> buffer;
    std::string result;
    std::unique_ptr<FILE, decltype(&pclose)> pipe(popen(cmd, "r"), pclose);
    if (!pipe) {
        throw std::runtime_error("popen() failed!");
    }
    while (fgets(buffer.data(), buffer.size(), pipe.get()) != nullptr) {
        result += buffer.data();
    }
    return result;
}

int main() {

    ifstream myfile;
    myfile.open("fpga_images.json");

    auto j3 = json::parse(myfile);

    myfile.close();

    //string s = j3["images"][0]["afi"] ;

    //cout << s << endl;

    auto j4 = json::parse(cmd_exec("cat fpga_images.json"));
    
    //cout << j4 << endl;

    int num_apps = j3["images"][0]["num_apps"];

    json j5;
    for (auto & x : j3["images"]) {
        cout << x << endl;
        j5.push_back(x);
    }

    cout << "Contains " << j3["images"].size() << " images " << endl;

    cout << "Empty size: " << j5.size() << " isEmpty: " << j5.empty() << endl;

    json j6;

    j6["myIsh"]["woah"] = 5;

    //cout << j6["myIsh"].key() << endl;

    return 0;

}