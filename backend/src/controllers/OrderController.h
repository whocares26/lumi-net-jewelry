#pragma once
#include <drogon/HttpController.h>
class OrderController : public drogon::HttpController<OrderController> {
public:
    METHOD_LIST_BEGIN
    ADD_METHOD_TO(OrderController::getAll,      "/api/orders",              drogon::Get);
    ADD_METHOD_TO(OrderController::getOne,      "/api/orders/{1}",          drogon::Get);
    ADD_METHOD_TO(OrderController::create,      "/api/orders",              drogon::Post);
    ADD_METHOD_TO(OrderController::updateStatus,"/api/orders/{1}/status",   drogon::Put);
    METHOD_LIST_END
    void getAll      (const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&);
    void getOne      (const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&,int);
    void create      (const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&);
    void updateStatus(const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&,int);
};
