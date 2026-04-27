#pragma once
#include <drogon/HttpController.h>
class SupplierController : public drogon::HttpController<SupplierController> {
public:
    METHOD_LIST_BEGIN
    ADD_METHOD_TO(SupplierController::getAll, "/api/suppliers",     drogon::Get);
    ADD_METHOD_TO(SupplierController::create, "/api/suppliers",     drogon::Post);
    ADD_METHOD_TO(SupplierController::update, "/api/suppliers/{1}", drogon::Put);
    ADD_METHOD_TO(SupplierController::remove, "/api/suppliers/{1}", drogon::Delete);
    METHOD_LIST_END
    void getAll(const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&);
    void create(const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&);
    void update(const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&,int);
    void remove(const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&,int);
};
