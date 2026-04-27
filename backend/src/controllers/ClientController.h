#pragma once
#include <drogon/HttpController.h>
class ClientController : public drogon::HttpController<ClientController> {
public:
    METHOD_LIST_BEGIN
    ADD_METHOD_TO(ClientController::getAll, "/api/clients",     drogon::Get);
    ADD_METHOD_TO(ClientController::getOne, "/api/clients/{1}", drogon::Get);
    ADD_METHOD_TO(ClientController::update, "/api/clients/{1}", drogon::Put);
    METHOD_LIST_END
    void getAll(const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&);
    void getOne(const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&,int);
    void update(const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&,int);
};
