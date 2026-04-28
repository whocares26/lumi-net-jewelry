#include "InfoController.h"
#include <drogon/drogon.h>
using namespace drogon;
static HttpResponsePtr cors(HttpResponsePtr r){r->addHeader("Access-Control-Allow-Origin","*");return r;}
static HttpResponsePtr jsonErr(const std::string& m,HttpStatusCode c=k400BadRequest){
    Json::Value j;j["error"]=m;auto r=HttpResponse::newHttpJsonResponse(j);r->setStatusCode(c);return cors(r);}

// GET /api/cashiers/:snils/store
void InfoController::cashierStore(const HttpRequestPtr&,
    std::function<void(const HttpResponsePtr&)>&& cb, std::string snils){
    app().getDbClient()->execSqlAsync(
        "SELECT s.store_id,s.store_address,s.store_phone "
        "FROM STORE s WHERE s.manager_snils=("
        "  SELECT manager_snils FROM CASHIER WHERE cashier_snils=$1)",
        [cb](const orm::Result& r){
            if(r.empty()) return cb(jsonErr("Магазин кассира не найден",k404NotFound));
            const auto row=r[0]; Json::Value o;
            o["id"]      = row["store_id"].as<int>();
            o["address"] = row["store_address"].as<std::string>();
            o["phone"]   = row["store_phone"].as<std::string>();
            auto resp=HttpResponse::newHttpJsonResponse(o);
            resp->addHeader("Access-Control-Allow-Origin","*"); cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        snils);
}

// GET /api/managers/:snils/store
void InfoController::managerStore(const HttpRequestPtr&,
    std::function<void(const HttpResponsePtr&)>&& cb, std::string snils){
    app().getDbClient()->execSqlAsync(
        "SELECT store_id,store_address,store_phone FROM STORE WHERE manager_snils=$1",
        [cb](const orm::Result& r){
            if(r.empty()) return cb(jsonErr("Магазин менеджера не найден",k404NotFound));
            const auto row=r[0]; Json::Value o;
            o["id"]      = row["store_id"].as<int>();
            o["address"] = row["store_address"].as<std::string>();
            o["phone"]   = row["store_phone"].as<std::string>();
            auto resp=HttpResponse::newHttpJsonResponse(o);
            resp->addHeader("Access-Control-Allow-Origin","*"); cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        snils);
}

// GET /api/products/:article/stock-all — остатки во всех магазинах
void InfoController::productStocks(const HttpRequestPtr&,
    std::function<void(const HttpResponsePtr&)>&& cb, int article){
    app().getDbClient()->execSqlAsync(
        "SELECT st.stock_quantity,s.store_id,s.store_address "
        "FROM STOCK st JOIN STORE s ON st.store_id=s.store_id "
        "WHERE st.product_article=$1 ORDER BY st.stock_quantity DESC",
        [cb](const orm::Result& r){
            Json::Value arr(Json::arrayValue);
            for(const auto& row:r){Json::Value o;
                o["qty"]     = row["stock_quantity"].as<int>();
                o["store_id"]= row["store_id"].as<int>();
                o["address"] = row["store_address"].as<std::string>();
                arr.append(o);}
            auto resp=HttpResponse::newHttpJsonResponse(arr);
            resp->addHeader("Access-Control-Allow-Origin","*"); cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        article);
}
