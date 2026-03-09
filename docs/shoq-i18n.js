/**
 * shoq-i18n.js
 *
 * Lightweight i18n for Shoq static HTML pages.
 *
 * Usage:
 *   1. Add <script src="shoq-i18n.js"></script> in <head>.
 *   2. Mark translatable elements: <span data-i18n="key"></span>
 *      For attributes: <button data-i18n-title="key">
 *   3. Call ShoqI18n.init() on DOMContentLoaded.
 *
 * Language detection order:
 *   a. ?lang= query param (highest priority — for testing)
 *   b. localStorage 'shoq_lang'
 *   c. navigator.language / navigator.languages
 *   d. 'en' fallback
 */

const ShoqI18n = (() => {
  // ── Translations ────────────────────────────────────────────────────────
  const translations = {
    en: {
      pageTitle: 'Join Shoq Server',
      pageSubtitle: 'Invite Preview',
      pageNote: 'This page is for invite links only. If direct opening doesn\'t work, copy the code and join manually in the app.',
      selectLanguage: 'Select language',
      systemDefault: 'System default',
      invitePageInstructions: 'Use this invite code in the Shoq app.',
      inviteStep1: 'Open Shoq.',
      inviteStep2: 'Tap Join Server.',
      inviteStep3: 'Paste the invite code and confirm.',
      copyCode: 'Copy Code',
      openInShoq: 'Open in Shoq',
    },
    pt_PT: {
      pageTitle: 'Entrar no servidor Shoq',
      pageSubtitle: 'Pré-visualização do convite',
      pageNote: 'Esta página destina-se apenas a ligações de convite. Se a abertura direta não funcionar, copie o código e junte-se manualmente na aplicação.',
      selectLanguage: 'Selecionar idioma',
      systemDefault: 'Padrão do sistema',
      invitePageInstructions: 'Utilize este código de convite na aplicação Shoq.',
      inviteStep1: 'Abra o Shoq.',
      inviteStep2: 'Toque em Entrar no servidor.',
      inviteStep3: 'Cole o código de convite e confirme.',
      copyCode: 'Copiar código',
      openInShoq: 'Abrir no Shoq',
    },
    uk: {
      pageTitle: 'Приєднатися до сервера Shoq',
      pageSubtitle: 'Попередній перегляд запрошення',
      pageNote: 'Ця сторінка призначена лише для посилань-запрошень. Якщо пряме відкриття не спрацює, скопіюйте код і приєднайтеся вручну у застосунку.',
      selectLanguage: 'Виберіть мову',
      systemDefault: 'Системний за замовчуванням',
      invitePageInstructions: 'Використайте цей код запрошення у застосунку Shoq.',
      inviteStep1: 'Відкрийте Shoq.',
      inviteStep2: 'Натисніть «Приєднатися до сервера».',
      inviteStep3: 'Вставте код запрошення та підтвердіть.',
      copyCode: 'Скопіювати код',
      openInShoq: 'Відкрити в Shoq',
    },
  };

  const STORAGE_KEY = 'shoq_lang';
  const DEFAULT_LANG = 'en';
  const SUPPORTED_LANGS = Object.keys(translations);

  // ── Core functions ──────────────────────────────────────────────────────

  function getQueryParam(name) {
    const url = new URL(window.location);
    return url.searchParams.get(name);
  }

  function detectLanguage() {
    // 1. Query param (highest priority)
    const queryLang = getQueryParam('lang');
    if (queryLang && SUPPORTED_LANGS.includes(queryLang)) {
      return queryLang;
    }

    // 2. localStorage
    const saved = localStorage.getItem(STORAGE_KEY);
    if (saved && SUPPORTED_LANGS.includes(saved)) {
      return saved;
    }

    // 3. Browser language
    const navLang = navigator.language || navigator.userLanguage;
    const mainLang = navLang.split('-')[0]; // e.g., 'pt' from 'pt-PT'

    if (mainLang === 'pt') return 'pt_PT';
    if (mainLang === 'uk') return 'uk';
    if (mainLang === 'en') return 'en';

    // Also check navigator.languages
    if (navigator.languages && Array.isArray(navigator.languages)) {
      for (const lang of navigator.languages) {
        if (lang.startsWith('pt')) return 'pt_PT';
        if (lang.startsWith('uk')) return 'uk';
        if (lang.startsWith('en')) return 'en';
      }
    }

    // 4. Fallback
    return DEFAULT_LANG;
  }

  function setLanguage(lang) {
    if (!SUPPORTED_LANGS.includes(lang)) {
      lang = DEFAULT_LANG;
    }
    localStorage.setItem(STORAGE_KEY, lang);
    return lang;
  }

  function t(key, lang) {
    return (translations[lang] && translations[lang][key]) || 
           (translations[DEFAULT_LANG] && translations[DEFAULT_LANG][key]) || 
           key;
  }

  // ── DOM Updates ──────────────────────────────────────────────────────

  function updatePageTitle(lang) {
    document.title = t('pageTitle', lang);

    // Update meta i18n-title if present
    const metaTitle = document.querySelector('meta[name="i18n-title"]');
    if (metaTitle) {
      const titleKey = metaTitle.getAttribute('content');
      document.title = t(titleKey, lang);
    }
  }

  function translateElements(lang) {
    // Text content
    document.querySelectorAll('[data-i18n]').forEach((el) => {
      const key = el.getAttribute('data-i18n');
      el.textContent = t(key, lang);
    });

    // Attributes
    document.querySelectorAll('[data-i18n-title]').forEach((el) => {
      const key = el.getAttribute('data-i18n-title');
      el.title = t(key, lang);
    });

    document.querySelectorAll('[data-i18n-placeholder]').forEach((el) => {
      const key = el.getAttribute('data-i18n-placeholder');
      el.placeholder = t(key, lang);
    });

    document.querySelectorAll('[data-i18n-value]').forEach((el) => {
      const key = el.getAttribute('data-i18n-value');
      el.value = t(key, lang);
    });
  }

  function createLanguagePicker(currentLang, onChangeCallback) {
    const picker = document.getElementById('lang-picker');
    if (!picker) return;

    const langDisplay = {
      en: 'English',
      pt_PT: 'Português (PT)',
      uk: 'Українська',
    };

    const html = `
      <select id="shoq-lang-select" style="
        padding: 0.35rem 0.6rem;
        border-radius: 6px;
        border: 1px solid rgba(255,255,255,0.2);
        background: rgba(255,255,255,0.08);
        color: #e8e8f0;
        font-size: 0.875rem;
        cursor: pointer;
        font-family: inherit;
      ">
        ${SUPPORTED_LANGS.map((lang) => `
          <option value="${lang}" ${lang === currentLang ? 'selected' : ''}>
            ${langDisplay[lang]}
          </option>
        `).join('')}
      </select>
    `;

    picker.innerHTML = html;

    const select = picker.querySelector('#shoq-lang-select');
    select.addEventListener('change', (e) => {
      const newLang = e.target.value;
      onChangeCallback(newLang);
    });
  }

  // ── Public API ──────────────────────────────────────────────────────

  return {
    init(lang) {
      if (!lang) {
        lang = detectLanguage();
      }
      lang = setLanguage(lang);

      updatePageTitle(lang);
      translateElements(lang);
      createLanguagePicker(lang, (newLang) => {
        window.location.search = `?lang=${newLang}`;
      });

      return lang;
    },

    translate(key, lang) {
      return t(key, lang || detectLanguage());
    },
  };
})();

document.addEventListener('DOMContentLoaded', () => ShoqI18n.init());
