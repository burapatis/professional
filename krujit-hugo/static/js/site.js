// ครุจิต — site.js
// ใช้ร่วมกันทุกหน้า: header scroll state, mobile nav toggle, scroll reveal animation

document.addEventListener('DOMContentLoaded', () => {
  const header = document.querySelector('header.site');
  if (header) {
    window.addEventListener('scroll', () => {
      header.classList.toggle('scrolled', window.scrollY > 8);
    });
  }

  const menubtn = document.getElementById('menubtn');
  const mobilenav = document.getElementById('mobilenav');
  if (menubtn && mobilenav) {
    menubtn.addEventListener('click', () => {
      const open = mobilenav.style.display === 'flex';
      mobilenav.style.display = open ? 'none' : 'flex';
      menubtn.setAttribute('aria-expanded', String(!open));
    });
    mobilenav.querySelectorAll('a').forEach(a => a.addEventListener('click', () => {
      mobilenav.style.display = 'none';
    }));
  }

  if (!window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
    const obs = new IntersectionObserver((entries) => {
      entries.forEach(e => {
        if (e.isIntersecting) {
          e.target.classList.add('is-visible');
          obs.unobserve(e.target);
        }
      });
    }, { threshold: 0.12 });
    document.querySelectorAll('.reveal').forEach(el => obs.observe(el));
  } else {
    document.querySelectorAll('.reveal').forEach(el => el.classList.add('is-visible'));
  }
});
