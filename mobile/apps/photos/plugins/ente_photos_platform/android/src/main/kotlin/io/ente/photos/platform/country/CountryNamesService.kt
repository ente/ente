package io.ente.photos.platform.country

import java.util.Locale

data class CountryNames(
    val region: String?,
    val names: Map<String, String>,
    val nativeNames: Map<String, List<String>>,
)

class CountryNamesService {
    fun names(
        localeTag: String,
        nativeLocales: Map<String, List<String>>,
    ): CountryNames {
        val displayLocale = Locale.forLanguageTag(localeTag)
        return CountryNames(
            Locale.getDefault().country.ifEmpty { null },
            Locale.getISOCountries().associateWith { code ->
                Locale.Builder().setRegion(code).build().getDisplayCountry(displayLocale)
            },
            nativeLocales.mapValues { (code, localeTags) ->
                val country = Locale.Builder().setRegion(code).build()
                localeTags
                    .map { country.getDisplayCountry(Locale.forLanguageTag(it)) }
                    .filter { it.isNotEmpty() }
                    .distinct()
            },
        )
    }
}
