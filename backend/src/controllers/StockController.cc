#include "StockController.h"
#include <drogon/drogon.h>
using namespace drogon;
static HttpResponsePtr cors(HttpResponsePtr r){r->addHeader("Access-Control-Allow-Origin","*");return r;}
static HttpResponsePtr jsonErr(const std::string& m,HttpStatusCode c=k400BadRequest){
    Json::Value j;j["error"]=m;auto r=HttpResponse::newHttpJsonResponse(j);r->setStatusCode(c);return cors(r);}
void StockController::getByStore(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb,int storeId){
    std::string thresh=req->getParameter("threshold");
    app().getDbClient()->execSqlAsync(
        "SELECT st.stock_id,st.stock_quantity,p.product_article,p.product_name,p.product_category,p.product_price "
        "FROM STOCK st JOIN PRODUCT p ON st.product_article=p.product_article "
        "WHERE st.store_id=$1 AND ($2='' OR st.stock_quantity<=$2::int) "
        "ORDER BY st.stock_quantity ASC, p.product_name",
        [cb](const orm::Result& r){
            Json::Value arr(Json::arrayValue);
            for(auto& row:r){Json::Value o;
                o["stock_id"]=row["stock_id"].as<int>();
                o["qty"]=row["stock_quantity"].as<int>();
                o["article"]=row["product_article"].as<int>();
                o["name"]=row["product_name"].as<std::string>();
                o["category"]=row["product_category"].as<std::string>();
                o["price"]=row["product_price"].as<int>();
                arr.append(o);}
            auto resp=HttpResponse::newHttpJsonResponse(arr);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        storeId,thresh);
}
void StockController::updateQty(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb,int stockId){
    auto b=req->getJsonObject();if(!b)return cb(jsonErr("JSON required"));
    int qty=(*b)["qty"].asInt();int storeId=(*b)["store_id"].asInt();
    app().getDbClient()->execSqlAsync(
        "UPDATE STOCK SET stock_quantity=$1 WHERE stock_id=$2 AND store_id=$3",
        [cb](const orm::Result&){Json::Value o;o["ok"]=true;auto r=HttpResponse::newHttpJsonResponse(o);r->addHeader("Access-Control-Allow-Origin","*");cb(r);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},qty,stockId,storeId);
}
