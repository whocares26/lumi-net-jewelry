#pragma once
#include <drogon/HttpController.h>
class SaleController : public drogon::HttpController<SaleController> {
public:
    METHOD_LIST_BEGIN
    ADD_METHOD_TO(SaleController::getAll,      "/api/sales",              drogon::Get);
    ADD_METHOD_TO(SaleController::getOne,      "/api/sales/{1}",          drogon::Get);
    ADD_METHOD_TO(SaleController::create,      "/api/sales",              drogon::Post);
    ADD_METHOD_TO(SaleController::clientSales, "/api/clients/{1}/sales",  drogon::Get);
    METHOD_LIST_END
    void getAll     (const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&);
    void getOne     (const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&,int);
    void create     (const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&);
    void clientSales(const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&,int);
};
