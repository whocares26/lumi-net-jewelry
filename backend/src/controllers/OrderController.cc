#include "OrderController.h"
#include <drogon/drogon.h>
using namespace drogon;
static HttpResponsePtr cors(HttpResponsePtr r){r->addHeader("Access-Control-Allow-Origin","*");return r;}
static HttpResponsePtr jsonErr(const std::string& m,HttpStatusCode c=k400BadRequest){
    Json::Value j;j["error"]=m;auto r=HttpResponse::newHttpJsonResponse(j);r->setStatusCode(c);return cors(r);}

void OrderController::getAll(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb){
    std::string storeId=req->getParameter("store_id");
    std::string status=req->getParameter("status");
    std::string suppId=req->getParameter("supplier_id");
    app().getDbClient()->execSqlAsync(
        "SELECT o.order_id,o.order_date,o.order_status,o.order_total,"
        "s.store_address,sp.supplier_name,m.manager_fio "
        "FROM \"ORDER\" o "
        "JOIN STORE s ON o.store_id=s.store_id "
        "JOIN SUPPLIER sp ON o.supplier_id=sp.supplier_id "
        "JOIN MANAGER m ON o.manager_snils=m.manager_snils "
        "WHERE ($1='' OR o.store_id=$1::int) "
        "AND ($2='' OR o.order_status=$2) "
        "AND ($3='' OR o.supplier_id=$3::int) "
        "ORDER BY o.order_date DESC",
        [cb](const orm::Result& r){
            Json::Value arr(Json::arrayValue);
            for(auto& row:r){Json::Value o;
                o["id"]=row["order_id"].as<int>();
                o["date"]=row["order_date"].as<std::string>();
                o["status"]=row["order_status"].as<std::string>();
                o["total"]=row["order_total"].as<long long>();
                o["store"]=row["store_address"].as<std::string>();
                o["supplier"]=row["supplier_name"].as<std::string>();
                o["manager"]=row["manager_fio"].as<std::string>();
                arr.append(o);}
            auto resp=HttpResponse::newHttpJsonResponse(arr);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        storeId,status,suppId);
}

void OrderController::getOne(const HttpRequestPtr&,std::function<void(const HttpResponsePtr&)>&& cb,int id){
    app().getDbClient()->execSqlAsync(
        "SELECT o.*,s.store_address,sp.supplier_name,m.manager_fio "
        "FROM \"ORDER\" o JOIN STORE s ON o.store_id=s.store_id "
        "JOIN SUPPLIER sp ON o.supplier_id=sp.supplier_id "
        "JOIN MANAGER m ON o.manager_snils=m.manager_snils WHERE o.order_id=$1",
        [cb,id](const orm::Result& r){
            if(r.empty())return cb(jsonErr("Заказ не найден",k404NotFound));
            auto& row=r[0];Json::Value o;
            o["id"]=row["order_id"].as<int>();
            o["date"]=row["order_date"].as<std::string>();
            o["status"]=row["order_status"].as<std::string>();
            o["total"]=row["order_total"].as<long long>();
            o["store"]=row["store_address"].as<std::string>();
            o["supplier"]=row["supplier_name"].as<std::string>();
            o["manager"]=row["manager_fio"].as<std::string>();
            app().getDbClient()->execSqlAsync(
                "SELECT oi.order_item_quantity,p.product_name,p.product_article,p.product_price "
                "FROM ORDER_ITEM oi JOIN PRODUCT p ON oi.product_article=p.product_article WHERE oi.order_id=$1",
                [cb,o](const orm::Result& ri) mutable {
                    Json::Value items(Json::arrayValue);
                    for(auto& row2:ri){Json::Value itm;
                        itm["name"]=row2["product_name"].as<std::string>();
                        itm["article"]=row2["product_article"].as<int>();
                        itm["price"]=row2["product_price"].as<int>();
                        itm["qty"]=row2["order_item_quantity"].as<int>();
                        items.append(itm);}
                    o["items"]=items;
                    auto resp=HttpResponse::newHttpJsonResponse(o);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
                [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},id);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},id);
}

void OrderController::create(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb){
    auto b=req->getJsonObject();if(!b)return cb(jsonErr("JSON required"));
    int storeId=(*b)["store_id"].asInt();
    int suppId=(*b)["supplier_id"].asInt();
    Json::Value items=(*b)["items"];
    if(!items.isArray()||items.empty())return cb(jsonErr("items required"));

    // Build arrays for stored procedure
    std::string arts="ARRAY[",qtys="ARRAY[";
    for(unsigned i=0;i<items.size();i++){
        if(i)arts+=",",qtys+=",";
        arts+=std::to_string(items[i]["article"].asInt());
        qtys+=std::to_string(items[i]["qty"].asInt());}
    arts+="]::INT[]";qtys+="]::INT[]";

    std::string sql="CALL create_supplier_order("+std::to_string(storeId)+","+
                    std::to_string(suppId)+","+arts+","+qtys+",NULL)";
    app().getDbClient()->execSqlAsync(sql,
        [cb](const orm::Result&){Json::Value o;o["ok"]=true;
            auto r=HttpResponse::newHttpJsonResponse(o);r->setStatusCode(k201Created);r->addHeader("Access-Control-Allow-Origin","*");cb(r);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));});
}

void OrderController::updateStatus(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb,int id){
    auto b=req->getJsonObject();if(!b)return cb(jsonErr("JSON required"));
    std::string status=(*b)["status"].asString();
    app().getDbClient()->execSqlAsync(
        "UPDATE \"ORDER\" SET order_status=$1 WHERE order_id=$2",
        [cb](const orm::Result&){Json::Value o;o["ok"]=true;auto r=HttpResponse::newHttpJsonResponse(o);r->addHeader("Access-Control-Allow-Origin","*");cb(r);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},status,id);
}
