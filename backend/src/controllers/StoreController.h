#pragma once
#include <drogon/HttpController.h>
class StoreController : public drogon::HttpController<StoreController> {
public:
    METHOD_LIST_BEGIN
    ADD_METHOD_TO(StoreController::getAll, "/api/stores",     drogon::Get);
    ADD_METHOD_TO(StoreController::getOne, "/api/stores/{1}", drogon::Get);
    ADD_METHOD_TO(StoreController::create, "/api/stores",     drogon::Post);
    ADD_METHOD_TO(StoreController::update, "/api/stores/{1}", drogon::Put);
    ADD_METHOD_TO(StoreController::remove, "/api/stores/{1}", drogon::Delete);
    METHOD_LIST_END
    void getAll(const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&);
    void getOne(const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&,int);
    void create(const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&);
    void update(const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&,int);
    void remove(const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&,int);
};
