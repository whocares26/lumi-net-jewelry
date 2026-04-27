#include <drogon/drogon.h>
#include <iostream>

int main() {
    std::cout << "[lumi-net] Starting backend..." << std::endl;
    try {
        drogon::app()
            .loadConfigFile("/app/config.json")
            .run();
    } catch (const std::exception& e) {
        std::cerr << "[lumi-net] Fatal: " << e.what() << std::endl;
        return 1;
    }
    return 0;
}
