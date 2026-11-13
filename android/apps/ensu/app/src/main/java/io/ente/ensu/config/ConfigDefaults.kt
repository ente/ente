package io.ente.ensu.config

import io.ente.ensu.bindings.ConfigDefaults
import io.ente.ensu.bindings.configDefaults
import io.ente.ensu.bindings.uniffiEnsureInitialized

fun loadConfigDefaults(): ConfigDefaults {
    uniffiEnsureInitialized()
    return configDefaults()
}
