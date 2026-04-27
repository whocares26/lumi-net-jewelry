#pragma once
#include <drogon/HttpController.h>
class ProductController : public drogon::HttpController<ProductController> {
public:
    METHOD_LIST_BEGIN
    ADD_METHOD_TO(ProductController::getAll,    "/api/products",      drogon::Get);
    ADD_METHOD_TO(ProductController::getOne,    "/api/products/{1}",  drogon::Get);
    ADD_METHOD_TO(ProductController::create,    "/api/products",      drogon::Post);
    ADD_METHOD_TO(ProductController::update,    "/api/products/{1}",  drogon::Put);
    ADD_METHOD_TO(ProductController::remove,    "/api/products/{1}",  drogon::Delete);
    METHOD_LIST_END
    void getAll(const drogon::HttpRequestPtr&, std::function<void(const drogon::HttpResponsePtr&)>&&);
    void getOne(const drogon::HttpRequestPtr&, std::function<void(const drogon::HttpResponsePtr&)>&&, int);
    void create(const drogon::HttpRequestPtr&, std::function<void(const drogon::HttpResponsePtr&)>&&);
    void update(const drogon::HttpRequestPtr&, std::function<void(const drogon::HttpResponsePtr&)>&&, int);
    void remove(const drogon::HttpRequestPtr&, std::function<void(const drogon::HttpResponsePtr&)>&&, int);
};
