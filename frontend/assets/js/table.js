const TableHelper=(()=>{
  const configurations={usersTable:['Role','Municipality'],hazardsTable:['Type','Municipality'],safeZonesTable:['Municipality'],centersTable:['Municipality','Status'],alertsTable:['Type','Level','Municipality','Status'],historicalTable:['Disaster','Municipality']};
  function enhance(bodyId,labels){
    const body=document.getElementById(bodyId),table=body?.closest('table'),toolbar=table?.parentElement?.querySelector('.table-toolbar');if(!body||!table||!toolbar)return;
    const headers=[...table.tHead.rows[0].cells].map(cell=>cell.textContent.trim()),filterBox=document.createElement('div');filterBox.className='table-filters';toolbar.appendChild(filterBox);
    const filters=labels.map(label=>{const index=headers.findIndex(header=>header.toLowerCase().includes(label.toLowerCase()));if(index<0)return null;const select=document.createElement('select');select.dataset.column=index;select.innerHTML=`<option value="">All ${label.toLowerCase()}</option>`;select.addEventListener('change',apply);filterBox.appendChild(select);return select;}).filter(Boolean);
    function options(){filters.forEach(select=>{const current=select.value,values=[...body.rows].filter(row=>!row.querySelector('[colspan]')).map(row=>row.cells[Number(select.dataset.column)]?.innerText.trim()).filter(Boolean),unique=[...new Set(values)].sort();select.replaceChildren(new Option(`All ${headers[Number(select.dataset.column)].toLowerCase()}`,''),...unique.map(value=>new Option(value,value)));select.value=unique.includes(current)?current:'';});}
    function apply(){[...body.rows].forEach(row=>{if(row.querySelector('[colspan]'))return;row.hidden=filters.some(select=>select.value&&row.cells[Number(select.dataset.column)]?.innerText.trim()!==select.value);});}
    new MutationObserver(()=>{options();apply();}).observe(body,{childList:true});options();
  }
  function init(){Object.entries(configurations).forEach(([id,labels])=>enhance(id,labels));}
  return {init};
})();
document.readyState==='loading'?document.addEventListener('DOMContentLoaded',TableHelper.init):TableHelper.init();
