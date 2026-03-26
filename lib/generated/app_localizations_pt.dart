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

  @override
  String get settingsTitle => 'Definições';

  @override
  String get sectionNotifications => 'Notificações';

  @override
  String get sectionAppearance => 'Aspeto';

  @override
  String get friendRequestsTitle => 'Pedidos de amizade';

  @override
  String get friendRequestsSubtitle =>
      'Receba notificações quando alguém lhe envia um pedido de amizade';

  @override
  String get messagesTitle => 'Mensagens';

  @override
  String get messagesSubtitle =>
      'Receba notificações quando receber uma nova mensagem';

  @override
  String get textSize => 'Tamanho do texto';

  @override
  String textSizeSubtitle(int percent) {
    return '$percent% - Multiplicador do tamanho do texto';
  }

  @override
  String get welcomeBack => 'Bem-vindo de volta';

  @override
  String get signInToContinue => 'Inicie sessão para continuar';

  @override
  String get rememberMe => 'Lembrar-me';

  @override
  String get dontHaveAnAccount => 'Não tem conta? ';

  @override
  String get alreadyHaveAnAccount => 'Já tem conta? ';

  @override
  String get acceptTermsPrefix => 'Aceito os ';

  @override
  String get couldNotOpenLink => 'Não foi possível abrir a ligação';

  @override
  String get accountCreatedVerificationSent =>
      'Conta criada. Foi enviado um e-mail de verificação. Valide-o a partir deste ecrã.';

  @override
  String get verifyYourEmail => 'Verifique o seu e-mail';

  @override
  String get verificationEmailSentTo =>
      'Enviámos um e-mail de verificação para:';

  @override
  String get verificationWindowsHint =>
      'A verificação automática é executada em segundo plano no Windows. Se não atualizar, toque em \"Já verifiquei o meu e-mail\".';

  @override
  String resendInSeconds(int seconds) {
    return 'Reenviar em $seconds segundos';
  }

  @override
  String get emailNotVerifiedYet =>
      'O e-mail ainda não foi verificado. Verifique a sua caixa de entrada.';

  @override
  String get iveVerifiedMyEmail => 'Já verifiquei o meu e-mail';

  @override
  String logoutFailed(String error) {
    return 'Falha ao terminar sessão: $error';
  }

  @override
  String get createAction => 'Criar';

  @override
  String get createFolder => 'Criar pasta';

  @override
  String get createGroupChat => 'Criar grupo';

  @override
  String get createServer => 'Criar servidor';

  @override
  String get folderName => 'Nome da pasta';

  @override
  String get folderNameHint => 'Trabalho, Família, Gaming...';

  @override
  String get folderAlreadyExists => 'A pasta já existe';

  @override
  String get defaultUser => 'Utilizador';

  @override
  String get addFriendsFirstToCreateRoom =>
      'Adicione amigos primeiro para criar uma sala';

  @override
  String get createGroup => 'Criar grupo';

  @override
  String get groupName => 'Nome do grupo';

  @override
  String get groupNameHint => 'Projeto de fim de semana';

  @override
  String get selectMembers => 'Selecionar membros';

  @override
  String get selectAtLeastOneMember => 'Selecione pelo menos um membro';

  @override
  String get serverName => 'Nome do servidor';

  @override
  String get serverNameHint => 'O meu servidor';

  @override
  String get serverIconPersonalizeHint =>
      'Pode personalizar o ícone do servidor em Perfil do servidor.';

  @override
  String get inviteLinkOrCode => 'Ligação ou código de convite';

  @override
  String get pasteInviteLinkOrServerCode =>
      'Cole a ligação de convite ou o código do servidor';

  @override
  String get enterValidInviteLinkOrCode =>
      'Introduza uma ligação de convite ou código válido';

  @override
  String get join => 'Entrar';

  @override
  String get inviteLinkInvalid => 'A ligação de convite é inválida';

  @override
  String get inviteLinkExpired => 'Esta ligação de convite expirou';

  @override
  String get serverNotFoundForInvite =>
      'Servidor não encontrado para este convite';

  @override
  String get permissionDeniedJoiningServer =>
      'Permissão negada ao entrar no servidor. Atualize as regras do Firestore para convites de servidor e entradas em conversas.';

  @override
  String couldNotJoinServer(String error) {
    return 'Não foi possível entrar no servidor: $error';
  }

  @override
  String couldNotJoinServerCode(String code) {
    return 'Não foi possível entrar no servidor ($code)';
  }

  @override
  String get atLeastTwoMembersRequired =>
      'São necessários pelo menos 2 membros';

  @override
  String get permissionDeniedCreatingRoom =>
      'Permissão negada ao criar a sala. Verifique as regras do Firestore para conversas.';

  @override
  String failedToCreateRoom(String error) {
    return 'Falha ao criar a sala: $error';
  }

  @override
  String failedToCreateRoomCode(String code) {
    return 'Falha ao criar a sala ($code)';
  }

  @override
  String moveConversation(String name) {
    return 'Mover \"$name\"';
  }

  @override
  String get allChats => 'Todas as conversas';

  @override
  String get createFolderFirst => 'Crie primeiro uma pasta';

  @override
  String get groupLabel => 'Grupo';

  @override
  String get serverLabel => 'Servidor';

  @override
  String get groupChat => 'Grupo';

  @override
  String get searchChats => 'Pesquisar conversas...';

  @override
  String get folder => 'Pasta';

  @override
  String get myProfile => 'O meu perfil';

  @override
  String get myFriends => 'Os meus amigos';

  @override
  String get about => 'Sobre';

  @override
  String get aboutDescription =>
      'Aplicação de mensagens segura com encriptação de ponta a ponta.';

  @override
  String get notLoggedIn => 'Sessão não iniciada';

  @override
  String genericError(String error) {
    return 'Erro: $error';
  }

  @override
  String get chatOptions => 'Opções do chat';

  @override
  String get moveToFolder => 'Mover para pasta';

  @override
  String removeFromFolder(String name) {
    return 'Remover de $name';
  }

  @override
  String get noChatsYet => 'Ainda não há conversas';

  @override
  String get addFriendsToStartChatting =>
      'Adicione amigos para começar a conversar';

  @override
  String get addFriends => 'Adicionar amigos';

  @override
  String noChatsInFolder(String name) {
    return 'Não há conversas em $name';
  }

  @override
  String get moveChatHereHint =>
      'Mova uma conversa para aqui a partir do menu de qualquer conversa.';

  @override
  String get yesterday => 'Ontem';

  @override
  String daysAgo(int days) {
    return '${days}d atrás';
  }

  @override
  String get sentAMessage => 'Enviou uma mensagem';

  @override
  String get startChatting => 'Comece a conversar';

  @override
  String couldNotOpenInvite(String error) {
    return 'Não foi possível abrir o convite: $error';
  }

  @override
  String get friendsTitle => 'Amigos';

  @override
  String get myQrCode => 'O meu código QR';

  @override
  String get addFriend => 'Adicionar amigo';

  @override
  String get requestsTitle => 'Pedidos';

  @override
  String get blockedTitle => 'Bloqueados';

  @override
  String get searchFriends => 'Pesquisar amigos';

  @override
  String get noFriendsYet => 'Ainda não há amigos';

  @override
  String get sendFriendRequestsToConnect =>
      'Envie pedidos de amizade para se ligar';

  @override
  String noFriendsMatch(String filter) {
    return 'Nenhum amigo corresponde a \"$filter\"';
  }

  @override
  String get noFriendRequests => 'Sem pedidos de amizade';

  @override
  String get noBlockedUsers => 'Sem utilizadores bloqueados';

  @override
  String get unblock => 'Desbloquear';

  @override
  String get invalidUserData => 'Dados de utilizador inválidos';

  @override
  String get cannotAddYourself => 'Não pode adicionar-se a si próprio';

  @override
  String get alreadyFriends => 'Já são amigos';

  @override
  String get friendRequestAlreadySent => 'Pedido de amizade já enviado';

  @override
  String friendRequestSentTo(String name) {
    return 'Pedido de amizade enviado para $name!';
  }

  @override
  String get friendRequestAccepted => 'Pedido de amizade aceite!';

  @override
  String get friendRequestDenied => 'Pedido de amizade recusado';

  @override
  String get userBlocked => 'Utilizador bloqueado';

  @override
  String get userUnblocked => 'Utilizador desbloqueado';

  @override
  String get removeFriend => 'Remover amigo';

  @override
  String removeFriendConfirm(String name) {
    return 'Tem a certeza de que pretende remover $name dos seus amigos?';
  }

  @override
  String get remove => 'Remover';

  @override
  String get friendRemoved => 'Amigo removido';

  @override
  String get removeFriendMenu => 'Remover amigo';

  @override
  String get block => 'Bloquear';
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

  @override
  String get settingsTitle => 'Definições';

  @override
  String get sectionNotifications => 'Notificações';

  @override
  String get sectionAppearance => 'Aspeto';

  @override
  String get friendRequestsTitle => 'Pedidos de amizade';

  @override
  String get friendRequestsSubtitle =>
      'Receba notificações quando alguém lhe envia um pedido de amizade';

  @override
  String get messagesTitle => 'Mensagens';

  @override
  String get messagesSubtitle =>
      'Receba notificações quando receber uma nova mensagem';

  @override
  String get textSize => 'Tamanho do texto';

  @override
  String textSizeSubtitle(int percent) {
    return '$percent% - Multiplicador do tamanho do texto';
  }

  @override
  String get welcomeBack => 'Bem-vindo de volta';

  @override
  String get signInToContinue => 'Inicie sessão para continuar';

  @override
  String get rememberMe => 'Lembrar-me';

  @override
  String get dontHaveAnAccount => 'Não tem conta? ';

  @override
  String get alreadyHaveAnAccount => 'Já tem conta? ';

  @override
  String get acceptTermsPrefix => 'Aceito os ';

  @override
  String get couldNotOpenLink => 'Não foi possível abrir a ligação';

  @override
  String get accountCreatedVerificationSent =>
      'Conta criada. Foi enviado um e-mail de verificação. Valide-o a partir deste ecrã.';

  @override
  String get verifyYourEmail => 'Verifique o seu e-mail';

  @override
  String get verificationEmailSentTo =>
      'Enviámos um e-mail de verificação para:';

  @override
  String get verificationWindowsHint =>
      'A verificação automática é executada em segundo plano no Windows. Se não atualizar, toque em \"Já verifiquei o meu e-mail\".';

  @override
  String resendInSeconds(int seconds) {
    return 'Reenviar em $seconds segundos';
  }

  @override
  String get emailNotVerifiedYet =>
      'O e-mail ainda não foi verificado. Verifique a sua caixa de entrada.';

  @override
  String get iveVerifiedMyEmail => 'Já verifiquei o meu e-mail';

  @override
  String logoutFailed(String error) {
    return 'Falha ao terminar sessão: $error';
  }

  @override
  String get createAction => 'Criar';

  @override
  String get createFolder => 'Criar pasta';

  @override
  String get createGroupChat => 'Criar grupo';

  @override
  String get createServer => 'Criar servidor';

  @override
  String get folderName => 'Nome da pasta';

  @override
  String get folderNameHint => 'Trabalho, Família, Gaming...';

  @override
  String get folderAlreadyExists => 'A pasta já existe';

  @override
  String get defaultUser => 'Utilizador';

  @override
  String get addFriendsFirstToCreateRoom =>
      'Adicione amigos primeiro para criar uma sala';

  @override
  String get createGroup => 'Criar grupo';

  @override
  String get groupName => 'Nome do grupo';

  @override
  String get groupNameHint => 'Projeto de fim de semana';

  @override
  String get selectMembers => 'Selecionar membros';

  @override
  String get selectAtLeastOneMember => 'Selecione pelo menos um membro';

  @override
  String get serverName => 'Nome do servidor';

  @override
  String get serverNameHint => 'O meu servidor';

  @override
  String get serverIconPersonalizeHint =>
      'Pode personalizar o ícone do servidor em Perfil do servidor.';

  @override
  String get inviteLinkOrCode => 'Ligação ou código de convite';

  @override
  String get pasteInviteLinkOrServerCode =>
      'Cole a ligação de convite ou o código do servidor';

  @override
  String get enterValidInviteLinkOrCode =>
      'Introduza uma ligação de convite ou código válido';

  @override
  String get join => 'Entrar';

  @override
  String get inviteLinkInvalid => 'A ligação de convite é inválida';

  @override
  String get inviteLinkExpired => 'Esta ligação de convite expirou';

  @override
  String get serverNotFoundForInvite =>
      'Servidor não encontrado para este convite';

  @override
  String get permissionDeniedJoiningServer =>
      'Permissão negada ao entrar no servidor. Atualize as regras do Firestore para convites de servidor e entradas em conversas.';

  @override
  String couldNotJoinServer(String error) {
    return 'Não foi possível entrar no servidor: $error';
  }

  @override
  String couldNotJoinServerCode(String code) {
    return 'Não foi possível entrar no servidor ($code)';
  }

  @override
  String get atLeastTwoMembersRequired =>
      'São necessários pelo menos 2 membros';

  @override
  String get permissionDeniedCreatingRoom =>
      'Permissão negada ao criar a sala. Verifique as regras do Firestore para conversas.';

  @override
  String failedToCreateRoom(String error) {
    return 'Falha ao criar a sala: $error';
  }

  @override
  String failedToCreateRoomCode(String code) {
    return 'Falha ao criar a sala ($code)';
  }

  @override
  String moveConversation(String name) {
    return 'Mover \"$name\"';
  }

  @override
  String get allChats => 'Todas as conversas';

  @override
  String get createFolderFirst => 'Crie primeiro uma pasta';

  @override
  String get groupLabel => 'Grupo';

  @override
  String get serverLabel => 'Servidor';

  @override
  String get groupChat => 'Grupo';

  @override
  String get searchChats => 'Pesquisar conversas...';

  @override
  String get folder => 'Pasta';

  @override
  String get myProfile => 'O meu perfil';

  @override
  String get myFriends => 'Os meus amigos';

  @override
  String get about => 'Sobre';

  @override
  String get aboutDescription =>
      'Aplicação de mensagens segura com encriptação de ponta a ponta.';

  @override
  String get notLoggedIn => 'Sessão não iniciada';

  @override
  String genericError(String error) {
    return 'Erro: $error';
  }

  @override
  String get chatOptions => 'Opções do chat';

  @override
  String get moveToFolder => 'Mover para pasta';

  @override
  String removeFromFolder(String name) {
    return 'Remover de $name';
  }

  @override
  String get noChatsYet => 'Ainda não há conversas';

  @override
  String get addFriendsToStartChatting =>
      'Adicione amigos para começar a conversar';

  @override
  String get addFriends => 'Adicionar amigos';

  @override
  String noChatsInFolder(String name) {
    return 'Não há conversas em $name';
  }

  @override
  String get moveChatHereHint =>
      'Mova uma conversa para aqui a partir do menu de qualquer conversa.';

  @override
  String get yesterday => 'Ontem';

  @override
  String daysAgo(int days) {
    return '${days}d atrás';
  }

  @override
  String get sentAMessage => 'Enviou uma mensagem';

  @override
  String get startChatting => 'Comece a conversar';

  @override
  String couldNotOpenInvite(String error) {
    return 'Não foi possível abrir o convite: $error';
  }

  @override
  String get friendsTitle => 'Amigos';

  @override
  String get myQrCode => 'O meu código QR';

  @override
  String get addFriend => 'Adicionar amigo';

  @override
  String get requestsTitle => 'Pedidos';

  @override
  String get blockedTitle => 'Bloqueados';

  @override
  String get searchFriends => 'Pesquisar amigos';

  @override
  String get noFriendsYet => 'Ainda não há amigos';

  @override
  String get sendFriendRequestsToConnect =>
      'Envie pedidos de amizade para se ligar';

  @override
  String noFriendsMatch(String filter) {
    return 'Nenhum amigo corresponde a \"$filter\"';
  }

  @override
  String get noFriendRequests => 'Sem pedidos de amizade';

  @override
  String get noBlockedUsers => 'Sem utilizadores bloqueados';

  @override
  String get unblock => 'Desbloquear';

  @override
  String get invalidUserData => 'Dados de utilizador inválidos';

  @override
  String get cannotAddYourself => 'Não pode adicionar-se a si próprio';

  @override
  String get alreadyFriends => 'Já são amigos';

  @override
  String get friendRequestAlreadySent => 'Pedido de amizade já enviado';

  @override
  String friendRequestSentTo(String name) {
    return 'Pedido de amizade enviado para $name!';
  }

  @override
  String get friendRequestAccepted => 'Pedido de amizade aceite!';

  @override
  String get friendRequestDenied => 'Pedido de amizade recusado';

  @override
  String get userBlocked => 'Utilizador bloqueado';

  @override
  String get userUnblocked => 'Utilizador desbloqueado';

  @override
  String get removeFriend => 'Remover amigo';

  @override
  String removeFriendConfirm(String name) {
    return 'Tem a certeza de que pretende remover $name dos seus amigos?';
  }

  @override
  String get remove => 'Remover';

  @override
  String get friendRemoved => 'Amigo removido';

  @override
  String get removeFriendMenu => 'Remover amigo';

  @override
  String get block => 'Bloquear';
}
