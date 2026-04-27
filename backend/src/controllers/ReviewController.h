#pragma once
#include <drogon/HttpController.h>
class ReviewController : public drogon::HttpController<ReviewController> {
public:
    METHOD_LIST_BEGIN
    ADD_METHOD_TO(ReviewController::getAll, "/api/reviews",     drogon::Get);
    ADD_METHOD_TO(ReviewController::create, "/api/reviews",     drogon::Post);
    ADD_METHOD_TO(ReviewController::remove, "/api/reviews/{1}", drogon::Delete);
    METHOD_LIST_END
    void getAll(const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&);
    void create(const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&);
    void remove(const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&,int);
};
