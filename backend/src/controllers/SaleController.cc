#include "SaleController.h"
#include <drogon/drogon.h>
using namespace drogon;
static HttpResponsePtr cors(HttpResponsePtr r){r->addHeader("Access-Control-Allow-Origin","*");return r;}
static HttpResponsePtr jsonErr(const std::string& m,HttpStatusCode c=k400BadRequest){
    Json::Value j;j["error"]=m;auto r=HttpResponse::newHttpJsonResponse(j);r->setStatusCode(c);return cors(r);}

void SaleController::getAll(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb){
    std::string storeId=req->getParameter("store_id");
    std::string from=req->getParameter("from");
    std::string to=req->getParameter("to");
    app().getDbClient()->execSqlAsync(
        "SELECT s.sale_id,s.sale_date,s.sale_total,s.sale_payment_method,"
        "c.client_fio,c.client_phone,st.store_address,ca.cashier_fio "
        "FROM SALE s "
        "JOIN CLIENT c ON s.client_id=c.client_id "
        "JOIN STORE st ON s.store_id=st.store_id "
        "JOIN CASHIER ca ON s.cashier_snils=ca.cashier_snils "
        "WHERE ($1='' OR s.store_id=$1::int) "
        "AND ($2='' OR s.sale_date>=$2::date) "
        "AND ($3='' OR s.sale_date<=$3::date) "
        "ORDER BY s.sale_date DESC LIMIT 200",
        [cb](const orm::Result& r){
            Json::Value arr(Json::arrayValue);
            for(const auto& row:r){Json::Value o;
                o["id"]=row["sale_id"].as<int>();
                o["date"]=row["sale_date"].as<std::string>();
                o["total"]=row["sale_total"].as<double>();
                o["payment"]=row["sale_payment_method"].as<std::string>();
                o["client"]=row["client_fio"].isNull()?"":row["client_fio"].as<std::string>();
                o["client_phone"]=row["client_phone"].as<std::string>();
                o["store"]=row["store_address"].as<std::string>();
                o["cashier"]=row["cashier_fio"].as<std::string>();
                arr.append(o);}
            auto resp=HttpResponse::newHttpJsonResponse(arr);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        storeId,from,to);
}

void SaleController::getOne(const HttpRequestPtr&,std::function<void(const HttpResponsePtr&)>&& cb,int id){
    app().getDbClient()->execSqlAsync(
        "SELECT s.*,c.client_fio,c.client_phone,st.store_address,ca.cashier_fio "
        "FROM SALE s JOIN CLIENT c ON s.client_id=c.client_id "
        "JOIN STORE st ON s.store_id=st.store_id "
        "JOIN CASHIER ca ON s.cashier_snils=ca.cashier_snils WHERE s.sale_id=$1",
        [cb,id](const orm::Result& r){
            if(r.empty())return cb(jsonErr("Продажа не найдена",k404NotFound));
            const auto row=r[0];Json::Value o;
            o["id"]=row["sale_id"].as<int>();
            o["date"]=row["sale_date"].as<std::string>();
            o["total"]=row["sale_total"].as<double>();
            o["payment"]=row["sale_payment_method"].as<std::string>();
            o["client"]=row["client_fio"].isNull()?"":row["client_fio"].as<std::string>();
            o["store"]=row["store_address"].as<std::string>();
            o["cashier"]=row["cashier_fio"].as<std::string>();
            app().getDbClient()->execSqlAsync(
                "SELECT si.sale_item_quantity,p.product_name,p.product_article,p.product_price "
                "FROM SALE_ITEM si JOIN PRODUCT p ON si.product_article=p.product_article WHERE si.sale_id=$1",
                [cb,o](const orm::Result& ri) mutable {
                    Json::Value items(Json::arrayValue);
                    for(const auto& row2:ri){Json::Value itm;
                        itm["name"]=row2["product_name"].as<std::string>();
                        itm["article"]=row2["product_article"].as<int>();
                        itm["price"]=row2["product_price"].as<int>();
                        itm["qty"]=row2["sale_item_quantity"].as<int>();
                        items.append(itm);}
                    o["items"]=items;
                    auto resp=HttpResponse::newHttpJsonResponse(o);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
                [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},id);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},id);
}

void SaleController::create(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb){
    auto b=req->getJsonObject();if(!b)return cb(jsonErr("JSON required"));
    int clientId=(*b)["client_id"].asInt();
    std::string cashierSnils=(*b)["cashier_snils"].asString();
    int storeId=(*b)["store_id"].asInt();
    std::string payment=(*b)["payment_method"].asString();
    Json::Value items=(*b)["items"];
    if(!items.isArray()||items.empty())return cb(jsonErr("items обязателен и не должен быть пустым"));
    double total=0;
    for(const auto& itm:items) total+=itm["price"].asDouble()*itm["qty"].asInt();
    auto db=app().getDbClient();
    db->execSqlAsync(
        "INSERT INTO SALE(client_id,cashier_snils,store_id,sale_total,sale_payment_method,sale_date) "
        "VALUES($1,$2,$3,$4,$5,CURRENT_DATE) RETURNING sale_id",
        [cb,items,db](const orm::Result& r){
            int saleId=r[0]["sale_id"].as<int>();
            int itemIdx=1;
            for(const auto& itm:items){
                int art=itm["article"].asInt();int qty=itm["qty"].asInt();
                db->execSqlAsync(
                    "INSERT INTO SALE_ITEM(sale_id,sale_item_id,product_article,sale_item_quantity) VALUES($1,$2,$3,$4)",
                    [](const orm::Result&){},[](const orm::DrogonDbException&){},saleId,itemIdx++,art,qty);}
            Json::Value o;o["id"]=saleId;o["ok"]=true;
            auto resp=HttpResponse::newHttpJsonResponse(o);resp->setStatusCode(k201Created);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        clientId,cashierSnils,storeId,total,payment);
}

void SaleController::clientSales(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb,int clientId){
    std::string from=req->getParameter("from");
    std::string to=req->getParameter("to");
    app().getDbClient()->execSqlAsync(
        "SELECT s.sale_id,s.sale_date,s.sale_total,s.sale_payment_method,st.store_address,"
        "array_agg(p.product_name) AS products "
        "FROM SALE s JOIN STORE st ON s.store_id=st.store_id "
        "JOIN SALE_ITEM si ON s.sale_id=si.sale_id "
        "JOIN PRODUCT p ON si.product_article=p.product_article "
        "WHERE s.client_id=$1 AND ($2='' OR s.sale_date>=$2::date) AND ($3='' OR s.sale_date<=$3::date) "
        "GROUP BY s.sale_id,st.store_address ORDER BY s.sale_date DESC",
        [cb](const orm::Result& r){
            Json::Value arr(Json::arrayValue);
            for(const auto& row:r){Json::Value o;
                o["id"]=row["sale_id"].as<int>();
                o["date"]=row["sale_date"].as<std::string>();
                o["total"]=row["sale_total"].as<double>();
                o["payment"]=row["sale_payment_method"].as<std::string>();
                o["store"]=row["store_address"].as<std::string>();
                o["products"]=row["products"].as<std::string>();
                arr.append(o);}
            auto resp=HttpResponse::newHttpJsonResponse(arr);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        clientId,from,to);
}
