#include "ProductController.h"
#include <drogon/drogon.h>
using namespace drogon;

static HttpResponsePtr cors(HttpResponsePtr r){r->addHeader("Access-Control-Allow-Origin","*");return r;}
static HttpResponsePtr jsonErr(const std::string& m,HttpStatusCode c=k400BadRequest){
    Json::Value j;j["error"]=m;auto r=HttpResponse::newHttpJsonResponse(j);r->setStatusCode(c);return cors(r);}

void ProductController::getAll(const HttpRequestPtr& req, std::function<void(const HttpResponsePtr&)>&& cb){
    std::string cat  = req->getParameter("category");
    std::string srch = req->getParameter("search");
    std::string storeId = req->getParameter("store_id");
    std::string sql;
    std::vector<std::string> params;
    if(!storeId.empty()){
        sql="SELECT p.product_article,p.product_name,p.product_category,p.product_price,"
            "COALESCE(s.stock_quantity,0) AS stock_quantity "
            "FROM PRODUCT p LEFT JOIN STOCK s ON p.product_article=s.product_article AND s.store_id=$1 "
            "WHERE ($2='' OR p.product_category=$2) AND ($3='' OR lower(p.product_name) LIKE lower('%'||$3||'%')) "
            "ORDER BY p.product_category,p.product_name";
        params={storeId, cat, srch};
    } else {
        sql="SELECT product_article,product_name,product_category,product_price FROM PRODUCT "
            "WHERE ($1='' OR product_category=$1) AND ($2='' OR lower(product_name) LIKE lower('%'||$2||'%')) "
            "ORDER BY product_category,product_name";
        params={cat, srch};
    }
    auto db=app().getDbClient();
    auto exec=[cb,sql,params,db](){
        if(params.size()==3)
            db->execSqlAsync(sql,[cb](const orm::Result& r){
                Json::Value arr(Json::arrayValue);
                for(auto& row:r){Json::Value o;
                    o["article"]=row["product_article"].as<int>();
                    o["name"]=row["product_name"].as<std::string>();
                    o["category"]=row["product_category"].as<std::string>();
                    o["price"]=row["product_price"].as<int>();
                    if(row.columnIndex("stock_quantity")>=0 && !row["stock_quantity"].isNull())
                        o["stock_quantity"]=row["stock_quantity"].as<int>();
                    arr.append(o);}
                auto resp=HttpResponse::newHttpJsonResponse(arr);
                resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);
            },[cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
            params[0],params[1],params[2]);
        else
            db->execSqlAsync(sql,[cb](const orm::Result& r){
                Json::Value arr(Json::arrayValue);
                for(auto& row:r){Json::Value o;
                    o["article"]=row["product_article"].as<int>();
                    o["name"]=row["product_name"].as<std::string>();
                    o["category"]=row["product_category"].as<std::string>();
                    o["price"]=row["product_price"].as<int>();
                    arr.append(o);}
                auto resp=HttpResponse::newHttpJsonResponse(arr);
                resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);
            },[cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
            params[0],params[1]);
    };
    exec();
}

void ProductController::getOne(const HttpRequestPtr&,std::function<void(const HttpResponsePtr&)>&& cb,int art){
    app().getDbClient()->execSqlAsync(
        "SELECT * FROM PRODUCT WHERE product_article=$1",
        [cb](const orm::Result& r){
            if(r.empty())return cb(jsonErr("Товар не найден",k404NotFound));
            Json::Value o;auto& row=r[0];
            o["article"]=row["product_article"].as<int>();
            o["name"]=row["product_name"].as<std::string>();
            o["category"]=row["product_category"].as<std::string>();
            o["price"]=row["product_price"].as<int>();
            auto resp=HttpResponse::newHttpJsonResponse(o);
            resp->addHeader("Access-Control-Allow-Origin","*");cb(resp);
        },[cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},art);
}

void ProductController::create(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb){
    auto b=req->getJsonObject();
    if(!b)return cb(jsonErr("Требуется JSON"));
    int art=(*b)["article"].asInt();
    std::string name=(*b)["name"].asString();
    std::string cat=(*b)["category"].asString();
    int price=(*b)["price"].asInt();
    app().getDbClient()->execSqlAsync(
        "INSERT INTO PRODUCT(product_article,product_name,product_category,product_price) VALUES($1,$2,$3,$4)",
        [cb](const orm::Result&){
            Json::Value o;o["ok"]=true;
            auto r=HttpResponse::newHttpJsonResponse(o);r->setStatusCode(k201Created);
            r->addHeader("Access-Control-Allow-Origin","*");cb(r);
        },[cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        art,name,cat,price);
}

void ProductController::update(const HttpRequestPtr& req,std::function<void(const HttpResponsePtr&)>&& cb,int art){
    auto b=req->getJsonObject();if(!b)return cb(jsonErr("Требуется JSON"));
    std::string name=(*b)["name"].asString();
    std::string cat=(*b)["category"].asString();
    int price=(*b)["price"].asInt();
    app().getDbClient()->execSqlAsync(
        "UPDATE PRODUCT SET product_name=$1,product_category=$2,product_price=$3 WHERE product_article=$4",
        [cb](const orm::Result&){Json::Value o;o["ok"]=true;
            auto r=HttpResponse::newHttpJsonResponse(o);r->addHeader("Access-Control-Allow-Origin","*");cb(r);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},
        name,cat,price,art);
}

void ProductController::remove(const HttpRequestPtr&,std::function<void(const HttpResponsePtr&)>&& cb,int art){
    app().getDbClient()->execSqlAsync(
        "DELETE FROM PRODUCT WHERE product_article=$1",
        [cb](const orm::Result&){Json::Value o;o["ok"]=true;
            auto r=HttpResponse::newHttpJsonResponse(o);r->addHeader("Access-Control-Allow-Origin","*");cb(r);},
        [cb](const orm::DrogonDbException& e){cb(jsonErr(e.base().what(),k500InternalServerError));},art);
}
