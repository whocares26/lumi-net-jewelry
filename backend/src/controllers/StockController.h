#pragma once
#include <drogon/HttpController.h>
class StockController : public drogon::HttpController<StockController> {
public:
    METHOD_LIST_BEGIN
    ADD_METHOD_TO(StockController::getByStore, "/api/stores/{1}/stock",  drogon::Get);
    ADD_METHOD_TO(StockController::updateQty,  "/api/stock/{1}",         drogon::Put);
    METHOD_LIST_END
    void getByStore(const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&,int);
    void updateQty (const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&,int);
};
