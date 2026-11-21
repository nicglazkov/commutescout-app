package com.commutescout.drive

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Google sign-in on Android needs the project's Web client as the server
 * client id. The iOS client broke every Android sign-in with [28444].
 */
class SignInClientTest {
    private fun repoFile(path: String): File? =
        generateSequence(File("").absoluteFile) { it.parentFile }
            .map { File(it, path) }
            .firstOrNull { it.exists() }

    @Test fun serverClientIdIsNotTheIosClient() {
        val yml = repoFile("ios/project.yml") ?: return
        val ios = Regex("""GIDClientID:\s*(\S+)""").find(yml.readText())?.groupValues?.get(1) ?: return
        assertNotEquals(ios, Account.WEB_CLIENT_ID)
    }

    @Test fun serverClientIdIsTheWebClientInGoogleServicesJson() {
        assertTrue(Account.WEB_CLIENT_ID.endsWith(".apps.googleusercontent.com"))
        // google-services.json is machine-local; CI restores it from a secret.
        val json = repoFile("android/app/google-services.json")?.readText() ?: return
        val web = Regex(""""client_id"\s*:\s*"([^"]+)"\s*,\s*"client_type"\s*:\s*3""").find(json)?.groupValues?.get(1)
            ?: return
        assertEquals(web, Account.WEB_CLIENT_ID)
    }
}
