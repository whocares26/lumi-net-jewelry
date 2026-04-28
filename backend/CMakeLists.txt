cmake_minimum_required(VERSION 3.15)
project(lumi_backend CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Drogon CONFIG REQUIRED)
find_package(OpenSSL REQUIRED)

set(SOURCES
    src/main.cc
    src/utils/JwtUtils.cc
    src/filters/CorsFilter.cc
    src/controllers/AuthController.cc
    src/controllers/ProductController.cc
    src/controllers/StoreController.cc
    src/controllers/SaleController.cc
    src/controllers/OrderController.cc
    src/controllers/StockController.cc
    src/controllers/ReportController.cc
    src/controllers/ClientController.cc
    src/controllers/SupplierController.cc
    src/controllers/ReviewController.cc
    src/controllers/InfoController.cc
)

add_executable(lumi_backend ${SOURCES})
target_link_libraries(lumi_backend PRIVATE Drogon::Drogon OpenSSL::Crypto)
target_include_directories(lumi_backend PRIVATE src)
