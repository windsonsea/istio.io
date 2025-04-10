---
title: Анонс Istio 1.23.5
linktitle: 1.23.5
subtitle: Патч-реліз
description: Патч-реліз Istio 1.23.5.
publishdate: 2025-02-13
release: 1.23.5
---

Цей реліз містить виправлення помилок для покращення надійності. Ця примітка до релізу описує, що змінилося між 1.23.4 та Istio 1.23.5.

{{< relnote >}}

## Зміни {#changes}

- **Виправлено** помилку, коли хости зі змішаним реністром в Gateway та TLS перенапрявлялись на неактуальний RDS.
  ([Issue #49638](https://github.com/istio/istio/issues/49638))

- **Виправлено** проблему коли политики режим ambient `PeerAuthentication` були занадто обмежувальними.
  ([Issue #53884](https://github.com/istio/istio/issues/53884))

- **Виправлено** помилку, коли декілька правил mTLS на рівні порту STRICT у політиці PeerAuthentication у зовнішньому режимі фактично призводили до політики дозволу через неправильну логіку оцінювання (AND проти OR).
  ([Issue #54146](https://github.com/istio/istio/issues/54146))

- **Виправлено** те, що нестандартні ревізії контролюють шлюзи, що не мають міток `istio.io/rev`.
  ([Issue #54280](https://github.com/istio/istio/issues/54280))

- **Виправлено** проблему, через яку нестабільність порядку журналу доступу призводила до розриву зʼєднання..
  ([Issue #54672](https://github.com/istio/istio/issues/54672))

- **Виправлено** ваду, коли Istiod надсилав несумісний формат журналу доступу до проксі-серверів <1.23.
  ([Issue #54795](https://github.com/istio/istio/issues/54795))

- **Покращено** веб-хук валідації Istiod для прийняття версій, про які він не знає. Це гарантує, що старіший Istio може перевіряти ресурси, створені новішими CRD.
