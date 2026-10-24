document.querySelectorAll('[data-password-toggle]').forEach(button=>button.addEventListener('click',()=>{const input=document.getElementById(button.dataset.passwordToggle);if(!input)return;input.type=input.type==='password'?'text':'password';button.textContent=input.type==='password'?'Show':'Hide';}));
const authFlash=sessionStorage.getItem('dm_auth_flash');if(authFlash){sessionStorage.removeItem('dm_auth_flash');try{const flash=JSON.parse(authFlash);Alerts.toast(flash.message,flash.icon||'success');}catch{}}

async function sendVerificationEmail(v){
  try{
    await emailjs.send(Config.EMAILJS_SERVICE_ID,Config.EMAILJS_VERIFY_TEMPLATE_ID,{to_email:v.to_email,to_name:v.to_name,code:v.code,expires_in_minutes:v.expires_in_minutes},{publicKey:Config.EMAILJS_PUBLIC_KEY});
    return true;
  }catch{return false;}
}

const registerForm=document.getElementById('registerForm');
if(registerForm){
  Api.get('/municipalities/options').then(rows=>rows.forEach(item=>registerForm.municipality_id.add(new Option(item.municipality_name,item.id)))).catch(error=>showError(error.message,error.errors));
  registerForm.addEventListener('submit',async event=>{
    event.preventDefault();if(!Alerts.validation(registerForm))return;
    const button=registerForm.querySelector('[type="submit"]');button.disabled=true;showLoading('Creating resident account…');
    try{
      const result=await Api.post('/auth/register',Object.fromEntries(new FormData(registerForm)));
      const v=result.verification;const emailSent=await sendVerificationEmail(v);
      sessionStorage.setItem('dm_auth_flash',JSON.stringify({
        message:emailSent?`Registration complete. We sent a 6-digit code to ${v.to_email}.`:'Registration complete, but the verification email could not be sent automatically. Use "Resend code" below.',
        icon:emailSent?'success':'warning'
      }));
      closeLoading();location.replace(`verify-email.html?email=${encodeURIComponent(v.to_email)}`);
    }catch(error){closeLoading();showError(error.message,error.errors);}
    finally{button.disabled=false;}
  });
}

const verifyForm=document.getElementById('verifyForm');
const resendBtn=document.getElementById('resendBtn');
if(verifyForm){
  const emailParam=new URLSearchParams(location.search).get('email');
  const emailVisible=verifyForm.emailVisible;
  if(emailParam){
    verifyForm.email.value=emailParam;
    document.getElementById('emailFieldLabel')?.remove();
  }else{
    emailVisible.required=true;
  }

  const otpBoxes=Array.from(document.querySelectorAll('.otp-box'));
  otpBoxes.forEach((box,index)=>{
    box.addEventListener('input',()=>{
      box.value=box.value.replace(/[^0-9]/g,'').slice(0,1);
      if(box.value&&index<otpBoxes.length-1)otpBoxes[index+1].focus();
    });
    box.addEventListener('keydown',event=>{
      if(event.key==='Backspace'&&!box.value&&index>0)otpBoxes[index-1].focus();
    });
    box.addEventListener('paste',event=>{
      event.preventDefault();
      const digits=(event.clipboardData.getData('text')||'').replace(/[^0-9]/g,'').slice(0,otpBoxes.length);
      digits.split('').forEach((digit,i)=>{if(otpBoxes[i])otpBoxes[i].value=digit;});
      otpBoxes[Math.min(digits.length,otpBoxes.length-1)].focus();
    });
  });

  function currentEmail(){return emailParam||emailVisible.value.trim();}

  verifyForm.addEventListener('submit',async event=>{
    event.preventDefault();
    if(!emailParam&&!Alerts.validation(verifyForm))return;
    const code=otpBoxes.map(box=>box.value).join('');
    if(code.length!==6){showError('Please enter the full 6-digit code.');return;}
    const button=verifyForm.querySelector('[type="submit"]');button.disabled=true;showLoading('Verifying…');
    try{
      const result=await Api.post('/auth/verify-email',{email:currentEmail(),code});
      sessionStorage.setItem('dm_auth_flash',JSON.stringify({message:result.message,icon:'success'}));
      closeLoading();location.replace('login.html');
    }catch(error){closeLoading();showError(error.message,error.errors);}
    finally{button.disabled=false;}
  });
  resendBtn?.addEventListener('click',async()=>{
    const email=currentEmail();
    if(!email){showError('Enter your email address first.');return;}
    resendBtn.disabled=true;showLoading('Sending a new code…');
    try{
      const result=await Api.post('/auth/resend-verification',{email});
      const v=result.verification;const emailSent=await sendVerificationEmail(v);
      closeLoading();
      await Alerts.success(emailSent?'Code sent':'Code generated',emailSent?`Check ${v.to_email} for your new verification code.`:'We generated a new code but could not email it automatically. Please try again shortly.');
    }catch(error){closeLoading();showError(error.message,error.errors);}
    finally{resendBtn.disabled=false;}
  });
}
const forgotForm=document.getElementById('forgotForm');
if(forgotForm)forgotForm.addEventListener('submit',async event=>{event.preventDefault();if(!Alerts.validation(forgotForm))return;showLoading('Requesting secure reset…');try{const result=await Api.post('/auth/forgot-password',Object.fromEntries(new FormData(forgotForm)));closeLoading();await Alerts.success('Request received',result.message);if(result.debug_reset_token)document.getElementById('developmentToken').textContent=`Development reset token: ${result.debug_reset_token}`;}catch(error){closeLoading();showError(error.message,error.errors);}});
const resetForm=document.getElementById('resetForm');
if(resetForm){const token=new URLSearchParams(location.search).get('token');if(token)resetForm.token.value=token;resetForm.addEventListener('submit',async event=>{event.preventDefault();if(!Alerts.validation(resetForm))return;showLoading('Updating password…');try{const result=await Api.post('/auth/reset-password',Object.fromEntries(new FormData(resetForm)));sessionStorage.setItem('dm_auth_flash',JSON.stringify({message:result.message,icon:'success'}));closeLoading();location.replace('login.html');}catch(error){closeLoading();showError(error.message,error.errors);}});}
