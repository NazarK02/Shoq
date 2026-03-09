// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get appTitle => 'Shoq';

  @override
  String get appTagline => 'Privado por design.';

  @override
  String get lightMode => 'Modo claro';

  @override
  String get darkMode => 'Modo escuro';

  @override
  String get darkThemeEnabled => 'Tema escuro ativado';

  @override
  String get lightThemeEnabled => 'Tema claro ativado';

  @override
  String get uiSize => 'Tamanho da interface';

  @override
  String uiSizeSubtitle(int percent) {
    return '$percent% · Interface maior ou menor';
  }

  @override
  String get reduceMotion => 'Reduzir movimento';

  @override
  String get reduceMotionSubtitle =>
      'Use menos animações para uma navegação mais fluida';

  @override
  String get linkPreviews => 'Pré-visualização de ligações';

  @override
  String get linkPreviewsSubtitle =>
      'Mostrar pré-visualizações de sites e YouTube nas mensagens';

  @override
  String get sectionGeneral => 'Geral';

  @override
  String get sectionPreferences => 'Preferências';

  @override
  String get sectionSupport => 'Suporte';

  @override
  String get sectionChat => 'Chat';

  @override
  String get privacy => 'Privacidade';

  @override
  String get privacySubtitle => 'Controle as suas definições de privacidade';

  @override
  String get security => 'Segurança';

  @override
  String get securitySubtitle => 'Palavra-passe e autenticação';

  @override
  String get language => 'Idioma';

  @override
  String get languageEnglish => 'English';

  @override
  String get languagePortuguese => 'Português (Portugal)';

  @override
  String get languageUkrainian => 'Українська';

  @override
  String get helpSupport => 'Ajuda e suporte';

  @override
  String get termsOfService => 'Termos de serviço';

  @override
  String get privacyPolicy => 'Política de privacidade';

  @override
  String get comingSoon => 'Em breve';

  @override
  String get languageComingSoon => 'Definições de idioma em breve';

  @override
  String get helpSupportComingSoon => 'Ajuda e suporte em breve';

  @override
  String get termsComingSoon => 'Termos de serviço em breve';

  @override
  String get privacySettingsComingSoon => 'Definições de privacidade em breve';

  @override
  String get securitySettingsComingSoon => 'Definições de segurança em breve';

  @override
  String get signIn => 'Iniciar sessão';

  @override
  String get signUp => 'Registar';

  @override
  String get signOut => 'Terminar sessão';

  @override
  String get createAccount => 'Criar conta';

  @override
  String get signUpToGetStarted => 'Registe-se para começar';

  @override
  String get email => 'E-mail';

  @override
  String get password => 'Palavra-passe';

  @override
  String get confirmPassword => 'Confirmar palavra-passe';

  @override
  String get fullName => 'Nome completo';

  @override
  String get forgotPassword => 'Esqueceu a palavra-passe?';

  @override
  String get continueWithGoogle => 'Continuar com o Google';

  @override
  String get orSeparator => 'ou';

  @override
  String get acceptTerms => 'Aceito os Termos e Condições';

  @override
  String get pleaseAcceptTerms => 'Por favor, aceite os Termos e Condições';

  @override
  String get pleaseEnterName => 'Por favor, insira o seu nome';

  @override
  String get pleaseEnterEmail => 'Por favor, insira o seu e-mail';

  @override
  String get pleaseEnterPassword => 'Por favor, insira uma palavra-passe';

  @override
  String get passwordTooShort =>
      'A palavra-passe deve ter pelo menos 6 caracteres';

  @override
  String get passwordsDoNotMatch => 'As palavras-passe não coincidem';

  @override
  String get pleaseConfirmPassword => 'Por favor, confirme a sua palavra-passe';

  @override
  String get verificationEmailSent =>
      'E-mail de verificação enviado! Verifique a sua caixa de entrada.';

  @override
  String get resendVerificationEmail => 'Reenviar e-mail de verificação';

  @override
  String get emailNotVerifiedTitle => 'Verifique o seu e-mail';

  @override
  String get emailNotVerifiedBody =>
      'Foi enviada uma ligação de verificação para o seu endereço de e-mail. Por favor, verifique a sua caixa de entrada e clique na ligação para continuar.';

  @override
  String get authErrorDefault => 'Ocorreu um erro';

  @override
  String get authErrorWeakPassword => 'A palavra-passe é demasiado fraca';

  @override
  String get authErrorEmailInUse => 'Já existe uma conta para este e-mail';

  @override
  String get authErrorInvalidEmail => 'Endereço de e-mail inválido';

  @override
  String get authErrorNotAllowed =>
      'Contas de e-mail/palavra-passe não estão ativadas';

  @override
  String get authErrorNetwork =>
      'Erro de rede. Por favor, verifique a sua ligação.';

  @override
  String get authErrorWrongPassword => 'Palavra-passe incorreta';

  @override
  String get authErrorUserNotFound =>
      'Não foi encontrada nenhuma conta para este e-mail';

  @override
  String get authErrorTooManyRequests =>
      'Demasiadas tentativas. Por favor, tente novamente mais tarde.';

  @override
  String get googleSignInUnsupportedLinux =>
      'O início de sessão com Google não é suportado no Linux. Utilize e-mail/palavra-passe.';

  @override
  String get googleSignInUnsupportedPlatform =>
      'O início de sessão com Google não é suportado nesta plataforma.';

  @override
  String get channels => 'Canais';

  @override
  String get serverProfile => 'Perfil do servidor';

  @override
  String get deleteChannel => 'Eliminar canal';

  @override
  String deleteChannelConfirm(String name) {
    return 'Eliminar #$name? As mensagens existentes ficam no histórico.';
  }

  @override
  String get cancel => 'Cancelar';

  @override
  String get delete => 'Eliminar';

  @override
  String get channelAlreadyExists => 'O canal já existe';

  @override
  String get selectVoiceChannelFirst => 'Selecione primeiro um canal de voz.';

  @override
  String get channelNoTextSupport =>
      'Este canal não suporta mensagens de texto.';

  @override
  String get channelNoStickerSupport => 'Este canal não suporta stickers.';

  @override
  String get useUploadButton =>
      'Use o botão de envio para partilhar ficheiros neste canal.';

  @override
  String failedToSend(String error) {
    return 'Falha ao enviar: $error';
  }

  @override
  String couldNotOpenChatRoom(String error) {
    return 'Não foi possível abrir a sala de chat: $error';
  }

  @override
  String dueDate(String date) {
    return 'Prazo: $date';
  }

  @override
  String get room => 'Sala';

  @override
  String get members => 'Membros';

  @override
  String get inviteCode => 'Código de convite';

  @override
  String get joinServer => 'Entrar no servidor';

  @override
  String get openInShoq => 'Abrir no Shoq';

  @override
  String get copyCode => 'Copiar código';

  @override
  String get codeCopied => 'Código copiado';

  @override
  String get invitePreview => 'Pré-visualização do convite';

  @override
  String get invitePageInstructions =>
      'Utilize este código de convite na aplicação Shoq.';

  @override
  String get inviteStep1 => 'Abra o Shoq.';

  @override
  String get inviteStep2 => 'Toque em Entrar no servidor.';

  @override
  String get inviteStep3 => 'Cole o código de convite e confirme.';

  @override
  String get invitePageNote =>
      'Esta página destina-se apenas a ligações de convite. Se a abertura direta não funcionar, copie o código e junte-se manualmente na aplicação.';

  @override
  String get qrScanTitle => 'Digitalizar código QR';

  @override
  String get qrShareTitle => 'O seu código QR';

  @override
  String get muteAudio => 'Silenciar';

  @override
  String get unmuteAudio => 'Ativar som';

  @override
  String get deafen => 'Ensurdecer';

  @override
  String get undeafen => 'Desensurdecer';

  @override
  String get leaveVoice => 'Sair da voz';

  @override
  String get voiceConnecting => 'A ligar…';

  @override
  String get voiceConnected => 'Ligado';

  @override
  String get voiceDisconnected => 'Desligado';

  @override
  String get activeVoiceSession => 'Sessão de voz ativa';

  @override
  String get returnToCall => 'Voltar à chamada';

  @override
  String get uploading => 'A enviar…';

  @override
  String get systemDefault => 'Padrão do sistema';

  @override
  String get selectLanguage => 'Selecionar idioma';
}

/// The translations for Portuguese, as used in Portugal (`pt_PT`).
class AppLocalizationsPtPt extends AppLocalizationsPt {
  AppLocalizationsPtPt() : super('pt_PT');

  @override
  String get appTitle => 'Shoq';

  @override
  String get appTagline => 'Privado por design.';

  @override
  String get lightMode => 'Modo claro';

  @override
  String get darkMode => 'Modo escuro';

  @override
  String get darkThemeEnabled => 'Tema escuro ativado';

  @override
  String get lightThemeEnabled => 'Tema claro ativado';

  @override
  String get uiSize => 'Tamanho da interface';

  @override
  String uiSizeSubtitle(int percent) {
    return '$percent% · Interface maior ou menor';
  }

  @override
  String get reduceMotion => 'Reduzir movimento';

  @override
  String get reduceMotionSubtitle =>
      'Use menos animações para uma navegação mais fluida';

  @override
  String get linkPreviews => 'Pré-visualização de ligações';

  @override
  String get linkPreviewsSubtitle =>
      'Mostrar pré-visualizações de sites e YouTube nas mensagens';

  @override
  String get sectionGeneral => 'Geral';

  @override
  String get sectionPreferences => 'Preferências';

  @override
  String get sectionSupport => 'Suporte';

  @override
  String get sectionChat => 'Chat';

  @override
  String get privacy => 'Privacidade';

  @override
  String get privacySubtitle => 'Controle as suas definições de privacidade';

  @override
  String get security => 'Segurança';

  @override
  String get securitySubtitle => 'Palavra-passe e autenticação';

  @override
  String get language => 'Idioma';

  @override
  String get languageEnglish => 'English';

  @override
  String get languagePortuguese => 'Português (Portugal)';

  @override
  String get languageUkrainian => 'Українська';

  @override
  String get helpSupport => 'Ajuda e suporte';

  @override
  String get termsOfService => 'Termos de serviço';

  @override
  String get privacyPolicy => 'Política de privacidade';

  @override
  String get comingSoon => 'Em breve';

  @override
  String get languageComingSoon => 'Definições de idioma em breve';

  @override
  String get helpSupportComingSoon => 'Ajuda e suporte em breve';

  @override
  String get termsComingSoon => 'Termos de serviço em breve';

  @override
  String get privacySettingsComingSoon => 'Definições de privacidade em breve';

  @override
  String get securitySettingsComingSoon => 'Definições de segurança em breve';

  @override
  String get signIn => 'Iniciar sessão';

  @override
  String get signUp => 'Registar';

  @override
  String get signOut => 'Terminar sessão';

  @override
  String get createAccount => 'Criar conta';

  @override
  String get signUpToGetStarted => 'Registe-se para começar';

  @override
  String get email => 'E-mail';

  @override
  String get password => 'Palavra-passe';

  @override
  String get confirmPassword => 'Confirmar palavra-passe';

  @override
  String get fullName => 'Nome completo';

  @override
  String get forgotPassword => 'Esqueceu a palavra-passe?';

  @override
  String get continueWithGoogle => 'Continuar com o Google';

  @override
  String get orSeparator => 'ou';

  @override
  String get acceptTerms => 'Aceito os Termos e Condições';

  @override
  String get pleaseAcceptTerms => 'Por favor, aceite os Termos e Condições';

  @override
  String get pleaseEnterName => 'Por favor, insira o seu nome';

  @override
  String get pleaseEnterEmail => 'Por favor, insira o seu e-mail';

  @override
  String get pleaseEnterPassword => 'Por favor, insira uma palavra-passe';

  @override
  String get passwordTooShort =>
      'A palavra-passe deve ter pelo menos 6 caracteres';

  @override
  String get passwordsDoNotMatch => 'As palavras-passe não coincidem';

  @override
  String get pleaseConfirmPassword => 'Por favor, confirme a sua palavra-passe';

  @override
  String get verificationEmailSent =>
      'E-mail de verificação enviado! Verifique a sua caixa de entrada.';

  @override
  String get resendVerificationEmail => 'Reenviar e-mail de verificação';

  @override
  String get emailNotVerifiedTitle => 'Verifique o seu e-mail';

  @override
  String get emailNotVerifiedBody =>
      'Foi enviada uma ligação de verificação para o seu endereço de e-mail. Por favor, verifique a sua caixa de entrada e clique na ligação para continuar.';

  @override
  String get authErrorDefault => 'Ocorreu um erro';

  @override
  String get authErrorWeakPassword => 'A palavra-passe é demasiado fraca';

  @override
  String get authErrorEmailInUse => 'Já existe uma conta para este e-mail';

  @override
  String get authErrorInvalidEmail => 'Endereço de e-mail inválido';

  @override
  String get authErrorNotAllowed =>
      'Contas de e-mail/palavra-passe não estão ativadas';

  @override
  String get authErrorNetwork =>
      'Erro de rede. Por favor, verifique a sua ligação.';

  @override
  String get authErrorWrongPassword => 'Palavra-passe incorreta';

  @override
  String get authErrorUserNotFound =>
      'Não foi encontrada nenhuma conta para este e-mail';

  @override
  String get authErrorTooManyRequests =>
      'Demasiadas tentativas. Por favor, tente novamente mais tarde.';

  @override
  String get googleSignInUnsupportedLinux =>
      'O início de sessão com Google não é suportado no Linux. Utilize e-mail/palavra-passe.';

  @override
  String get googleSignInUnsupportedPlatform =>
      'O início de sessão com Google não é suportado nesta plataforma.';

  @override
  String get channels => 'Canais';

  @override
  String get serverProfile => 'Perfil do servidor';

  @override
  String get deleteChannel => 'Eliminar canal';

  @override
  String deleteChannelConfirm(String name) {
    return 'Eliminar #$name? As mensagens existentes ficam no histórico.';
  }

  @override
  String get cancel => 'Cancelar';

  @override
  String get delete => 'Eliminar';

  @override
  String get channelAlreadyExists => 'O canal já existe';

  @override
  String get selectVoiceChannelFirst => 'Selecione primeiro um canal de voz.';

  @override
  String get channelNoTextSupport =>
      'Este canal não suporta mensagens de texto.';

  @override
  String get channelNoStickerSupport => 'Este canal não suporta stickers.';

  @override
  String get useUploadButton =>
      'Use o botão de envio para partilhar ficheiros neste canal.';

  @override
  String failedToSend(String error) {
    return 'Falha ao enviar: $error';
  }

  @override
  String couldNotOpenChatRoom(String error) {
    return 'Não foi possível abrir a sala de chat: $error';
  }

  @override
  String dueDate(String date) {
    return 'Prazo: $date';
  }

  @override
  String get room => 'Sala';

  @override
  String get members => 'Membros';

  @override
  String get inviteCode => 'Código de convite';

  @override
  String get joinServer => 'Entrar no servidor';

  @override
  String get openInShoq => 'Abrir no Shoq';

  @override
  String get copyCode => 'Copiar código';

  @override
  String get codeCopied => 'Código copiado';

  @override
  String get invitePreview => 'Pré-visualização do convite';

  @override
  String get invitePageInstructions =>
      'Utilize este código de convite na aplicação Shoq.';

  @override
  String get inviteStep1 => 'Abra o Shoq.';

  @override
  String get inviteStep2 => 'Toque em Entrar no servidor.';

  @override
  String get inviteStep3 => 'Cole o código de convite e confirme.';

  @override
  String get invitePageNote =>
      'Esta página destina-se apenas a ligações de convite. Se a abertura direta não funcionar, copie o código e junte-se manualmente na aplicação.';

  @override
  String get qrScanTitle => 'Digitalizar código QR';

  @override
  String get qrShareTitle => 'O seu código QR';

  @override
  String get muteAudio => 'Silenciar';

  @override
  String get unmuteAudio => 'Ativar som';

  @override
  String get deafen => 'Ensurdecer';

  @override
  String get undeafen => 'Desensurdecer';

  @override
  String get leaveVoice => 'Sair da voz';

  @override
  String get voiceConnecting => 'A ligar…';

  @override
  String get voiceConnected => 'Ligado';

  @override
  String get voiceDisconnected => 'Desligado';

  @override
  String get activeVoiceSession => 'Sessão de voz ativa';

  @override
  String get returnToCall => 'Voltar à chamada';

  @override
  String get uploading => 'A enviar…';

  @override
  String get systemDefault => 'Padrão do sistema';

  @override
  String get selectLanguage => 'Selecionar idioma';
}
