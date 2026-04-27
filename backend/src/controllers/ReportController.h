#pragma once
#include <drogon/HttpController.h>
class ReportController : public drogon::HttpController<ReportController> {
public:
    METHOD_LIST_BEGIN
    ADD_METHOD_TO(ReportController::salesByCategory, "/api/reports/sales-by-category", drogon::Get);
    ADD_METHOD_TO(ReportController::stockStatus,     "/api/reports/stock-status",      drogon::Get);
    ADD_METHOD_TO(ReportController::ordersBySupplier,"/api/reports/orders",            drogon::Get);
    ADD_METHOD_TO(ReportController::revenueByStore,  "/api/reports/revenue-by-store",  drogon::Get);
    ADD_METHOD_TO(ReportController::topCustomers,    "/api/reports/top-customers",     drogon::Get);
    METHOD_LIST_END
    void salesByCategory (const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&);
    void stockStatus     (const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&);
    void ordersBySupplier(const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&);
    void revenueByStore  (const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&);
    void topCustomers    (const drogon::HttpRequestPtr&,std::function<void(const drogon::HttpResponsePtr&)>&&);
};
