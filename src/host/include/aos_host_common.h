#ifndef AOS_HOST_COMMON
#define AOS_HOST_COMMON

#include "aos.h"
#include <cstdio>
#include <iostream>
#include <fstream>
#include <memory>
#include <stdexcept>
#include <string>
#include <array>
#include "json.hpp"
// FPGA specific includes
#include <fpga_pci.h>
#include <fpga_mgmt.h>
#include <fpga_dma.h>
#include <utils/lcd.h>
#include <utils/sh_dpi_tasks.h>
#include <ctime>

using json = nlohmann::json;
using std::cout;
using std::endl;
using std::flush;

std::string cmd_exec(std::string cmd);

void printErrorHost(std::string errStr);

#endif // AOS_HOST_COMMON