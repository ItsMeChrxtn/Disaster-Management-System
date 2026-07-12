const TableHelper=(()=>{
  const configurations={usersTable:['Role','Municipality'],hazardsTable:['Municipality'],safeZonesTable:['Municipality'],centersTable:['Municipality','Status'],alertsTable:['Type','Level','Municipality','Status'],historicalTable:['Disaster type','Municipality']};
  const alertStaticOptions={
    Type:['Weather Alert','Flood Alert','Earthquake Alert','Storm Surge Alert','Emergency Alert'],
    Level:['Info','Advisory','Warning','Critical'],
    Status:['Draft','Sent','Read','Unread']
  };
  const historicalDisasterTypes=[
    'Flood',
    'Flash Flood',
    'Typhoon',
    'Tropical Cyclone',
    'Storm',
    'Severe Thunderstorm',
    'Storm Surge',
    'Tornado',
    'Earthquake',
    'Tsunami',
    'Volcanic Eruption',
    'Lahar',
    'Landslide',
    'Mudslide',
    'Sinkhole',
    'Fire',
    'Forest Fire',
    'Drought',
    'Extreme Heat',
    'El Nino',
    'La Nina',
    'Disease Outbreak',
    'Epidemic',
    'Pandemic',
    'Chemical Spill',
    'Oil Spill',
    'Industrial Accident',
    'Transport Accident',
    'Structural Collapse',
    'Power Outage',
    'Coastal Erosion',
    'Other'
  ];
  function normalize(value){return String(value??'').trim().toLowerCase();}
  function optionKey(value){return normalize(value).replaceAll('_',' ');}
  function filterCellValue(row,select){
    if(select.dataset.label==='Disaster type'&&row.closest('tbody')?.id==='historicalTable')return row.querySelector('.history-record span:not(.history-record-icon)')?.innerText.trim()||'';
    return row.cells[Number(select.dataset.column)]?.innerText.trim()||'';
  }
  function currentUser(){try{return JSON.parse(sessionStorage.getItem('dm_user')||'{}');}catch{return{};}}
  function uniqueMunicipalities(rows=[]){const user=currentUser(),names=[...rows.map(row=>row.municipality_name||row.name).filter(Boolean),user.municipality_name].filter(Boolean),seen=new Set();return names.filter(name=>{const key=optionKey(name);if(seen.has(key))return false;seen.add(key);return true;}).sort((a,b)=>a.localeCompare(b));}
  async function loadMunicipalityRows(){try{return await Api.get('/municipalities/options');}catch{return[];}}
  function fillMunicipalitySelect(select,rows=[]){
    const current=select.value,names=uniqueMunicipalities(rows);
    select.dataset.static='true';
    select.replaceChildren(new Option('All municipality',''),new Option('Province-wide',optionKey('Province-wide')),...names.map(name=>new Option(name,optionKey(name))));
    select.value=[...select.options].some(option=>option.value===current)?current:'';
    select.dispatchEvent(new Event('change',{bubbles:true}));
  }
  async function hydrateAlertMunicipalityFilter(){
    const select=document.querySelector('#view-alerts .table-filters select[data-label="Municipality"]');
    if(!select||!window.Api?.get)return;
    fillMunicipalitySelect(select,[]);
    fillMunicipalitySelect(select,await loadMunicipalityRows());
  }
  async function hydrateHistoricalMunicipalityFilter(){
    const select=document.querySelector('#view-history .table-filters select[data-label="Municipality"]');
    if(!select||!window.Api?.get)return;
    fillMunicipalitySelect(select,[]);
    fillMunicipalitySelect(select,await loadMunicipalityRows());
  }
  function enhance(bodyId,labels){
    const body=document.getElementById(bodyId),table=body?.closest('table'),toolbar=table?.parentElement?.querySelector('.table-toolbar');if(!body||!table||!toolbar)return;
    const headers=[...table.tHead.rows[0].cells].map(cell=>cell.textContent.trim()),filterBox=document.createElement('div'),search=toolbar.querySelector('.table-search');filterBox.className='table-filters';filterBox.innerHTML='<span>Filter</span>';toolbar.appendChild(filterBox);
    if(bodyId==='hazardsTable'){
      toolbar.querySelector('.table-toolbar-title')?.insertAdjacentHTML('beforeend','<span id="hazardFilterCount" class="hazard-filter-count">Showing all hazards</span>');
      const typeSelect=document.createElement('select');typeSelect.id='hazardTypeFilter';typeSelect.setAttribute('aria-label','Filter by hazard type');typeSelect.innerHTML='<option value="">All type</option><option value="flood_zone">Flood</option><option value="storm_surge_area">Storm Surge</option><option value="landslide">Landslide</option><option value="earthquake_area">Earthquake</option><option value="fire">Fire</option><option value="other">Other</option>';filterBox.appendChild(typeSelect);
      const riskSelect=document.createElement('select');riskSelect.id='hazardRiskFilter';riskSelect.setAttribute('aria-label','Filter by risk level');riskSelect.innerHTML='<option value="">All risk</option><option value="low">Low</option><option value="moderate">Moderate</option><option value="high">High</option><option value="critical">Critical</option>';filterBox.appendChild(riskSelect);
    }
    const filters=labels.map(label=>{let index=headers.findIndex(header=>header.toLowerCase().includes(label.toLowerCase()));if(index<0&&bodyId==='historicalTable'&&label==='Disaster type')index=headers.findIndex(header=>header.toLowerCase()==='disaster');if(index<0)return null;const select=document.createElement('select');select.dataset.column=index;select.dataset.label=label;select.setAttribute('aria-label',`Filter by ${label}`);select.innerHTML=`<option value="">All ${label.toLowerCase()}</option>`;const staticValues=bodyId==='alertsTable'?alertStaticOptions[label]:bodyId==='historicalTable'&&label==='Disaster type'?historicalDisasterTypes:null;if(staticValues){select.dataset.static='true';select.append(...staticValues.map(value=>new Option(value,optionKey(value))));}select.addEventListener('change',apply);filterBox.appendChild(select);return select;}).filter(Boolean);
    if(search)filterBox.appendChild(search);
    if(bodyId==='alertsTable'){
      const municipality=filters.find(select=>select.dataset.label==='Municipality');
      if(municipality&&window.Api?.get){
        fillMunicipalitySelect(municipality,[]);
        loadMunicipalityRows().then(rows=>fillMunicipalitySelect(municipality,rows));
        [100,500,1200].forEach(delay=>setTimeout(hydrateAlertMunicipalityFilter,delay));
      }
    }
    if(bodyId==='historicalTable'){
      const municipality=filters.find(select=>select.dataset.label==='Municipality');
      if(municipality&&window.Api?.get){
        fillMunicipalitySelect(municipality,[]);
        loadMunicipalityRows().then(rows=>fillMunicipalitySelect(municipality,rows));
        [100,500,1200].forEach(delay=>setTimeout(hydrateHistoricalMunicipalityFilter,delay));
      }
    }
    function options(){filters.forEach(select=>{if(select.dataset.static==='true')return;const current=select.value,values=[...body.rows].filter(row=>!row.querySelector('[colspan]')).map(row=>filterCellValue(row,select)).filter(Boolean),unique=[...new Set(values)].sort();select.replaceChildren(new Option(`All ${select.dataset.label.toLowerCase()}`,''),...unique.map(value=>new Option(value,optionKey(value))));select.value=unique.map(optionKey).includes(current)?current:'';});}
    function apply(){[...body.rows].forEach(row=>{if(row.querySelector('[colspan]'))return;row.hidden=filters.some(select=>select.value&&optionKey(filterCellValue(row,select))!==select.value);});}
    new MutationObserver(()=>{options();apply();}).observe(body,{childList:true});options();
  }
  function init(){Object.entries(configurations).forEach(([id,labels])=>enhance(id,labels));}
  return {init};
})();
document.readyState==='loading'?document.addEventListener('DOMContentLoaded',TableHelper.init):TableHelper.init();
