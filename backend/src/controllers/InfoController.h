#pragma once
#include <drogon/HttpController.h>
class InfoController : public drogon::HttpController<InfoController> {
public:
    METHOD_LIST_BEGIN
    ADD_METHOD_TO(InfoController::cashierStore,  "/api/cashiers/{1}/store",       drogon::Get);
    ADD_METHOD_TO(InfoController::managerStore,  "/api/managers/{1}/store",       drogon::Get);
    ADD_METHOD_TO(InfoController::productStocks, "/api/products/{1}/stock-all",   drogon::Get);
    METHOD_LIST_END
    void cashierStore (const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&,std::string);
    void managerStore (const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&,std::string);
    void productStocks(const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&,int);
};
