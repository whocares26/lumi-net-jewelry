#include "StoreController.h"
#include <drogon/drogon.h>
using namespace drogon;
static HttpResponsePtr cors(HttpResponsePtr r){r->addHeader("Access-Control-Allow-Origin","*");return r;}
static HttpResponsePtr jsonErr(const std::string& m,HttpStatusCode c=k400BadRequest){
    Json::Value j;j["error"]=m;auto r=HttpResponse::newHttpJsonResponse(j);r->setStatusCode(c);return cors(r);}

void StoreController::getAll(const HttpRequestPtr&,std::function<void(const HttpResponsePtr&)>&& cb){
    app().getDbClient()->execSqlAsync(
        "SELECT s.store_id,s.store_address,s.store_phone,m.manager_fio "
        "FROM STORE s LEFT JOIN MANAGER m ON s.manager_snils=m.manager_snils ORDER BY s.store_id",
        [cb](const orm::Result& r){
            Json::Value arr(Json::arrayValue);
            for(auto& row:r){Json::Value o;
                o["id"]=row["store_id"].as<int>();
                o["address"]=row["store_address"].as<std::string>();
                o["phone"]=row["store_phone"].as<std::string>();
                o["manager"]=row["manager_fio"].isNull()?"":row["manager_fio"].as<std::string>();
                arr.append(o);}
            auto resp=HttpResponse::newHttpJsonResponse(arr);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));});
}
void StoreController::getOne(const HttpRequestPtr&,std::function<void(const HttpResponsePtr&)>&& cb,int id){
    app().getDbClient()->execSqlAsync(
        "SELECT s.store_id,s.store_address,s.store_phone,s.manager_snils,m.manager_fio "
        "FROM STORE s LEFT JOIN MANAGER m ON s.manager_snils=m.manager_snils WHERE s.store_id=$1",
        [cb](const orm::Result& r){
            if(r.empty())return cb(jsonErr("Магазин не найден",k404NotFound));
            auto& row=r[0];
            Json::Value o;
            o["id"]=row["store_id"].as<int>();
            o["address"]=row["store_address"].as<std::string>();
            o["phone"]=row["store_phone"].as<std::string>();
            o["manager"]=row["manager_fio"].isNull()?"":row["manager_fio"].as<std::string>();
            auto resp=HttpResponse::newHttpJsonResponse(o);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},id);
}
void StoreController::create(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb){
    auto b=req->getJsonObject();if(!b)return cb(jsonErr("JSON required"));
    std::string addr=(*b)["address"].asString(),phone=(*b)["phone"].asString();
    std::string msnils=(*b).get("manager_snils","").asString();
    app().getDbClient()->execSqlAsync(
        "INSERT INTO STORE(store_address,store_phone,manager_snils) VALUES($1,$2,NULLIF($3,'')) RETURNING store_id",
        [cb](const orm::Result& r){Json::Value o;o["id"]=r[0]["store_id"].as<int>();
            auto resp=HttpResponse::newHttpJsonResponse(o);resp->setStatusCode(k201Created);resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},addr,phone,msnils);
}
void StoreController::update(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb,int id){
    auto b=req->getJsonObject();if(!b)return cb(jsonErr("JSON required"));
    std::string addr=(*b)["address"].asString(),phone=(*b)["phone"].asString();
    std::string msnils=(*b).get("manager_snils","").asString();
    app().getDbClient()->execSqlAsync(
        "UPDATE STORE SET store_address=$1,store_phone=$2,manager_snils=NULLIF($3,'') WHERE store_id=$4",
        [cb](const orm::Result&){Json::Value o;o["ok"]=true;auto r=HttpResponse::newHttpJsonResponse(o);r->addHeader("Access-Control-Allow-Origin","*");cb(r);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},addr,phone,msnils,id);
}
void StoreController::remove(const HttpRequestPtr&,std::function<void(const HttpResponsePtr&)>&& cb,int id){
    app().getDbClient()->execSqlAsync("DELETE FROM STORE WHERE store_id=$1",
        [cb](const orm::Result&){Json::Value o;o["ok"]=true;auto r=HttpResponse::newHttpJsonResponse(o);r->addHeader("Access-Control-Allow-Origin","*");cb(r);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},id);
}
