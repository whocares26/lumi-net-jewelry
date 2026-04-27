#include "SupplierController.h"
#include <drogon/drogon.h>
using namespace drogon;
static HttpResponsePtr cors(HttpResponsePtr r){r->addHeader("Access-Control-Allow-Origin","*");return r;}
static HttpResponsePtr jsonErr(const std::string& m,HttpStatusCode c=k400BadRequest){
    Json::Value j;j["error"]=m;auto r=HttpResponse::newHttpJsonResponse(j);r->setStatusCode(c);return cors(r);}
void SupplierController::getAll(const HttpRequestPtr&,std::function<void(const HttpResponsePtr&)>&& cb){
    app().getDbClient()->execSqlAsync(
        "SELECT s.*,COUNT(o.order_id) AS order_count FROM SUPPLIER s LEFT JOIN \"ORDER\" o ON s.supplier_id=o.supplier_id GROUP BY s.supplier_id ORDER BY s.supplier_name",
        [cb](const orm::Result& r){
            Json::Value arr(Json::arrayValue);
            for(auto& row:r){Json::Value o;
                o["id"]=row["supplier_id"].as<int>();
                o["name"]=row["supplier_name"].as<std::string>();
                o["email"]=row["supplier_email"].as<std::string>();
                o["phone"]=row["supplier_phone"].as<std::string>();
                o["order_count"]=row["order_count"].as<int>();
                arr.append(o);}
            auto resp=HttpResponse::newHttpJsonResponse(arr);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));});
}
void SupplierController::create(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb){
    auto b=req->getJsonObject();if(!b)return cb(jsonErr("JSON required"));
    std::string name=(*b)["name"].asString(),email=(*b)["email"].asString(),phone=(*b)["phone"].asString();
    app().getDbClient()->execSqlAsync(
        "INSERT INTO SUPPLIER(supplier_name,supplier_email,supplier_phone) VALUES($1,$2,$3) RETURNING supplier_id",
        [cb](const orm::Result& r){Json::Value o;o["id"]=r[0]["supplier_id"].as<int>();
            auto resp=HttpResponse::newHttpJsonResponse(o);resp->setStatusCode(k201Created);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},name,email,phone);
}
void SupplierController::update(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb,int id){
    auto b=req->getJsonObject();if(!b)return cb(jsonErr("JSON required"));
    std::string name=(*b)["name"].asString(),email=(*b)["email"].asString(),phone=(*b)["phone"].asString();
    app().getDbClient()->execSqlAsync(
        "UPDATE SUPPLIER SET supplier_name=$1,supplier_email=$2,supplier_phone=$3 WHERE supplier_id=$4",
        [cb](const orm::Result&){Json::Value o;o["ok"]=true;auto r=HttpResponse::newHttpJsonResponse(o);r->addHeader("Access-Control-Allow-Origin","*");cb(r);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},name,email,phone,id);
}
void SupplierController::remove(const HttpRequestPtr&,std::function<void(const HttpResponsePtr&)>&& cb,int id){
    app().getDbClient()->execSqlAsync("DELETE FROM SUPPLIER WHERE supplier_id=$1",
        [cb](const orm::Result&){Json::Value o;o["ok"]=true;auto r=HttpResponse::newHttpJsonResponse(o);r->addHeader("Access-Control-Allow-Origin","*");cb(r);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},id);
}
