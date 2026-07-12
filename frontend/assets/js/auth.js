const form = document.getElementById('loginForm');
const error = document.getElementById('error');

if (Api.token()) location.href = sessionStorage.getItem('dm_force_password_change')==='1'?'profile.html?v=20260705-temp-password1':'dashboard.html?v=20260705-temp-password1';

form.addEventListener('submit', async event => {
  event.preventDefault();
  error.classList.add('hidden');

  const btn = form.querySelector('button[type="submit"]');
  btn.disabled = true;
  showLoading('Signing you in...');

  try {
    const data = Object.fromEntries(new FormData(form));
    const result = await Api.post('/auth/login', data);

    sessionStorage.setItem('dm_token', result.access_token);
    sessionStorage.setItem('dm_user', JSON.stringify(result.user));
    if(String(result.user.password_must_change||'0')==='1')sessionStorage.setItem('dm_force_password_change','1');
    else sessionStorage.removeItem('dm_force_password_change');
    sessionStorage.setItem('dm_flash', JSON.stringify({
      message: String(result.user.password_must_change||'0')==='1'?'Please change your temporary password.':`Welcome, ${result.user.fullname}.`,
      icon: 'success'
    }));

    closeLoading();
    location.replace(String(result.user.password_must_change||'0')==='1'?'profile.html?v=20260705-temp-password1':'dashboard.html?v=20260705-temp-password1');
  } catch (err) {
    closeLoading();
    await showError(err.message);
  } finally {
    btn.disabled = false;
  }
});
