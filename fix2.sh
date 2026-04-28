#!/bin/bash
# ================================================================
# lumi-net fix2 — точечные правки фронтенда (без ребилда бэкенда)
# Запуск: chmod +x fix2.sh && ./fix2.sh
# ================================================================
set -e
PROJ="$(cd "$(dirname "$0")" && pwd)"
JS="$PROJ/frontend/js/app.js"
GREEN='\033[0;32m'; BOLD='\033[1m'; NC='\033[0m'
ok()  { echo -e "${GREEN}✓${NC} $1"; }
hdr() { echo -e "\n${BOLD}━━━ $1 ━━━${NC}"; }

# ─────────────────────────────────────────────────────────────
# FIX 1: Заказы — «Все статусы» передаёт текст вместо ""
# Причина: <option>Все статусы</option> без value=""
# ─────────────────────────────────────────────────────────────
hdr "Fix 1: Заказы — фильтр статуса «Все»"
# Меняем генерацию опций для статусов заказов в pgOrders
# Было: statuses.map(s=>`<option ${s===statusF?'selected':''}>${s||'Все статусы'}</option>`)
# Стало: statuses.map(s=>`<option value="${s}" ...>${s||'Все статусы'}</option>`)
sed -i 's/statuses\.map(s=>`<option \${s===statusF?'\''selected'\'':'\'''\''}>..{s||'\''Все статусы'\''}<\/option>`)/PLACEHOLDER/g' "$JS" 2>/dev/null || true

# Точечная замена через Python (надёжнее чем sed для многострочного JS)
python3 - "$JS" << 'PYEOF'
import sys, re

path = sys.argv[1]
with open(path, 'r') as f:
    src = f.read()

# Fix 1: statuses select в pgOrders — добавить value=""
old1 = "statuses.map(s=>`<option ${s===statusF?'selected':''}>${s||'Все статусы'}</option>`).join('')}</select></div>"
new1 = "statuses.map(s=>`<option value=\"${s}\" ${s===statusF?'selected':''}>${s||'Все статусы'}</option>`).join('')}</select></div>"
src = src.replace(old1, new1)

# Fix 2: убрать кнопку "+ Новая продажа" для ADMIN и CASHIER в pgSales
# Было: const canAdd=ROLE==='ADMIN'||ROLE==='CASHIER';
# Стало: кнопка добавления продаж убирается для ADMIN и CASHIER в pgSales
old2 = "const canAdd=ROLE==='ADMIN'||ROLE==='CASHIER';"
new2 = "const canAdd=false; // продажа оформляется только через pgSaleNew"
src = src.replace(old2, new2)

# Fix 3: опечатка "поk." → "пок."
src = src.replace("} поk.", "} пок.")
src = src.replace("пок.", "пок.")  # уже правильное — no-op

# Fix 4: кнопка "Зарегистрировать?" в searchClientByPhone → открывает модал
old4 = '''el.innerHTML=`<div class="alert alert-err">Клиент с телефоном "${esc(phone)}" не найден. <a href="#" onclick="showRegForm()" style="color:var(--gold)">Зарегистрировать?</a></div>`;'''
new4 = '''el.innerHTML=`<div class="alert alert-err" style="display:flex;justify-content:space-between;align-items:center">
      <span>Клиент не найден: <b>${esc(phone)}</b></span>
      <button class="btn btn-outline btn-xs" onclick="modalRegisterClient('${esc(phone).replace(/'/g,'\\'')}')">+ Зарегистрировать</button>
    </div>`;'''
src = src.replace(old4, new4)

with open(path, 'w') as f:
    f.write(src)

print("Python patches applied")
PYEOF
ok "Fix 1: статус «Все» (value=\"\")"
ok "Fix 2: убрана кнопка «Новая продажа» из таблицы pgSales"
ok "Fix 3: опечатка поk. → пок."
ok "Fix 4: кнопка «Зарегистрировать» открывает модал"

# ─────────────────────────────────────────────────────────────
# FIX 5: Поиск клиента с autocomplete по телефонам всех клиентов
#         + модал быстрой регистрации прямо из формы продажи
# ─────────────────────────────────────────────────────────────
hdr "Fix 5: Autocomplete телефонов + модал регистрации"
python3 - "$JS" << 'PYEOF'
import sys

path = sys.argv[1]
with open(path, 'r') as f:
    src = f.read()

# Заменяем pgSaleNew — добавляем datalist с телефонами клиентов
old = '''    const storeId=MY_STORE?MY_STORE.id:'';
    const products=await get('/products',{store_id:storeId});
    saleCartItems=[];foundClient=null;'''

new = '''    const storeId=MY_STORE?MY_STORE.id:'';
    const [products, allClients]=await Promise.all([
      get('/products',{store_id:storeId}),
      get('/clients')
    ]);
    saleCartItems=[];foundClient=null;
    // Сохраняем для autocomplete
    window._allClients=allClients;'''
src = src.replace(old, new)

# Заменяем поле телефона в pgSaleNew — добавляем datalist
old2 = '''            <div style="display:flex;gap:8px;align-items:flex-end">
            <div class="form-group" style="flex:1;margin:0"><label>Номер телефона</label>
              <input id="sn-phone" type="text" placeholder="+7 (XXX) XXX-XX-XX"></div>
            <button class="btn btn-outline btn-sm" onclick="searchClientByPhone()">Найти</button>
          </div>'''

new2 = '''            <div style="display:flex;gap:8px;align-items:flex-end">
            <div class="form-group" style="flex:1;margin:0"><label>Номер телефона</label>
              <input id="sn-phone" type="text" placeholder="+7 (XXX) XXX-XX-XX"
                list="sn-phone-list"
                oninput="liveClientSearch(this.value)"
                autocomplete="off">
              <datalist id="sn-phone-list"></datalist>
            </div>
            <button class="btn btn-outline btn-sm" onclick="searchClientByPhone()">Найти</button>
          </div>'''
src = src.replace(old2, new2)

with open(path, 'w') as f:
    f.write(src)
print("pgSaleNew autocomplete injected")
PYEOF

# Добавляем функции liveClientSearch и modalRegisterClient в конец файла
# (перед строкой "// ── Init")
python3 - "$JS" << 'PYEOF'
import sys

path = sys.argv[1]
with open(path, 'r') as f:
    src = f.read()

insert = '''
// ── Live client search (autocomplete по телефону) ────────────
function liveClientSearch(val){
  const list=document.getElementById('sn-phone-list');
  if(!list)return;
  const clients=window._allClients||[];
  const q=val.replace(/\D/g,'');
  const matches=clients.filter(c=>c.phone.replace(/\D/g,'').includes(q)||
    (c.fio&&c.fio.toLowerCase().includes(val.toLowerCase()))).slice(0,10);
  list.innerHTML=matches.map(c=>`<option value="${c.phone}">${c.phone}${c.fio?' — '+c.fio:''}</option>`).join('');
  // Если точное совпадение — авто-выбрать
  const exact=clients.find(c=>c.phone===val);
  if(exact){
    foundClient=exact;
    const el=document.getElementById('sn-client-info');
    if(el)el.innerHTML=`<div class="alert alert-ok" style="display:flex;justify-content:space-between;align-items:center">
      <span>✓ <b>${esc(exact.fio||'Клиент')}</b> — ${esc(exact.phone)}</span>
      <span style="font-size:11px;color:var(--success)">ID: ${exact.id}</span></div>`;
  } else if(foundClient&&foundClient.phone!==val){
    foundClient=null;
    const el=document.getElementById('sn-client-info');
    if(el&&val.length>5)el.innerHTML='';
  }
}

// ── Модал быстрой регистрации клиента (для кассира) ──────────
function modalRegisterClient(prefillPhone=''){
  openModal('Быстрая регистрация клиента',`
    <div class="form-group"><label>ФИО</label>
      <input id="mr-fio" type="text" placeholder="Фамилия Имя Отчество"></div>
    <div class="form-group"><label>Телефон</label>
      <input id="mr-phone" type="text" value="${esc(prefillPhone)}" placeholder="+7 (XXX) XXX-XX-XX"></div>
    <div class="form-group"><label>Email (необязательно)</label>
      <input id="mr-email" type="email" placeholder="email@example.com"></div>
    <div style="font-size:12px;color:var(--smoke);margin-top:-8px">
      Клиент будет зарегистрирован в системе без создания личного кабинета.</div>`,
    `<button class="btn btn-ghost" onclick="closeModal()">Отмена</button>
     <button class="btn btn-primary" onclick="quickRegisterClient()">Зарегистрировать</button>`);
}
async function quickRegisterClient(){
  const fio  =document.getElementById('mr-fio').value.trim();
  const phone=document.getElementById('mr-phone').value.trim();
  const email=document.getElementById('mr-email').value.trim();
  if(!phone)return alert('Укажите телефон');
  try{
    // Создаём клиента напрямую через API
    const d=await post('/auth/register',{
      fio, phone, email,
      username:'client_'+Date.now(),
      password:'auto_'+Math.random().toString(36).slice(2,8)
    });
    closeModal();
    // Обновляем список клиентов
    window._allClients=await get('/clients').catch(()=>window._allClients||[]);
    // Ставим найденного клиента
    foundClient={id:d.client_id,fio,phone,email};
    const el=document.getElementById('sn-phone');
    if(el)el.value=phone;
    const info=document.getElementById('sn-client-info');
    if(info)info.innerHTML=`<div class="alert alert-ok">✓ Клиент <b>${esc(fio||phone)}</b> зарегистрирован</div>`;
  }catch(e){alert('Ошибка регистрации: '+e.message);}
}

'''

# Вставляем перед "// ── Init"
src = src.replace("// ── Init ─", insert + "// ── Init ─")

with open(path, 'w') as f:
    f.write(src)
print("liveClientSearch + modalRegisterClient injected")
PYEOF
ok "liveClientSearch (autocomplete)"
ok "modalRegisterClient (быстрая регистрация из кассы)"

# ─────────────────────────────────────────────────────────────
# Проверяем что файл не повреждён
# ─────────────────────────────────────────────────────────────
hdr "Проверка"
lines=$(wc -l < "$JS")
echo "app.js: $lines строк"
if [ "$lines" -lt 1000 ]; then
  echo -e "\033[0;31m⚠ Файл выглядит слишком коротким — проверьте вручную\033[0m"
else
  ok "app.js в норме"
fi

echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅  fix2 применён — ребилд НЕ нужен!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Перезапуск только frontend контейнера:"
echo -e "  \033[0;34mdocker compose restart lumi-frontend\033[0m"
echo ""
echo -e "  Или полный перезапуск без ребилда бэкенда:"
echo -e "  \033[0;34mdocker compose up\033[0m"
echo ""
