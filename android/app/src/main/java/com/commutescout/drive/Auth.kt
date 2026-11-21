package com.commutescout.drive

import android.app.Activity
import android.content.Context
import android.util.Log
import androidx.credentials.CredentialManager
import androidx.credentials.CustomCredential
import androidx.credentials.GetCredentialRequest
import androidx.credentials.exceptions.GetCredentialCancellationException
import com.google.android.libraries.identity.googleid.GetGoogleIdOption
import com.google.android.libraries.identity.googleid.GoogleIdTokenCredential
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.auth.FirebaseUser
import com.google.firebase.auth.GoogleAuthProvider
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.tasks.await
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * The same account as the website: one Firebase user, signed in with
 * Google. The ID token goes to commutescout.com as a Bearer header for
 * reports, watches and account settings.
 */
class Account(context: Context) {
    companion object {
        private const val TAG = "Account"
        // The Web application client from google-services.json (client_type 3):
        // the audience Firebase expects on Android ID tokens. Credential
        // Manager only accepts a Web client here; the iOS client id (the
        // app's GIDClientID) fails every sign-in with [28444] "Developer
        // console is not set up correctly".
        const val WEB_CLIENT_ID = "15002631928-uuvbtr9in3qnj2nlk9s72e75mcna2s5u.apps.googleusercontent.com"
    }

    private val auth = runCatching { FirebaseAuth.getInstance() }.getOrNull()
    private val _user = MutableStateFlow(auth?.currentUser)
    val user = _user.asStateFlow()
    private val _busy = MutableStateFlow(false)
    val busy = _busy.asStateFlow()
    private val _error = MutableStateFlow<String?>(null)
    val error = _error.asStateFlow()
    val available: Boolean get() = auth != null

    // The Terms agreement (TermsConsent): kept on this phone, asked once per version.
    private val termsPrefs = context.getSharedPreferences("cs.prefs", Context.MODE_PRIVATE)
    val termsAgreedHere: Boolean get() = TermsConsent.agreed(termsPrefs.getString(TermsConsent.PREF_KEY, null))
    private val _consentAsk = MutableStateFlow(false)
    /** True while a sign-in waits for the Terms dialog's answer. */
    val consentAsk = _consentAsk.asStateFlow()
    private var consentReply: kotlinx.coroutines.CompletableDeferred<Boolean>? = null

    /** The Terms dialog's answer: agreed and continue, or cancel. */
    fun answerConsent(agreed: Boolean) {
        if (agreed) termsPrefs.edit().putString(TermsConsent.PREF_KEY, TermsConsent.VERSION).apply()
        consentReply?.complete(agreed)
    }

    /** Asks for the agreement when this phone has not given it for the current version. */
    private suspend fun agreeFirst(): Boolean {
        if (termsAgreedHere) return true
        val reply = kotlinx.coroutines.CompletableDeferred<Boolean>()
        consentReply?.complete(false)
        consentReply = reply
        _consentAsk.value = true
        return try { reply.await() } finally { if (consentReply === reply) { consentReply = null; _consentAsk.value = false } }
    }

    /** The account records the agreement given on this phone; the server stamps the time. */
    suspend fun recordTerms() {
        if (!termsAgreedHere) return
        val t = token() ?: return
        runCatching { Backend.send("POST", "/api/me/terms", t, TermsConsent.body()) }
    }

    init {
        auth?.addAuthStateListener { _user.value = it.currentUser }
    }

    val signedIn: Boolean get() = _user.value != null
    val displayName: String get() = _user.value?.displayName ?: _user.value?.email ?: "Signed in"

    val email: String? get() = _user.value?.email
    /** The avatar letter. */
    val initial: String get() = displayName.trim().take(1).uppercase().ifEmpty { "?" }

    /** Today's API use and limits, from /api/keys; null when signed out or unreachable. */
    suspend fun apiUsage(): ApiUsage? {
        val t = token() ?: return null
        return runCatching { Backend.send("GET", "/api/keys", t) }.getOrNull()
            ?.takeIf { it.first in 200..299 }?.let { ApiUsage.parse(it.second) }
    }

    /** A fresh ID token for the server, or null when signed out. */
    suspend fun token(): String? = runCatching { _user.value?.getIdToken(false)?.await()?.token }.getOrNull()

    suspend fun signInWithGoogle(activity: Activity) {
        val auth = auth ?: run { _error.value = "Sign-in is not set up in this build."; return }
        // Signing in may create the account: the agreement comes first.
        if (!agreeFirst()) return
        _busy.value = true
        try {
            val option = GetGoogleIdOption.Builder()
                .setFilterByAuthorizedAccounts(false)
                .setServerClientId(WEB_CLIENT_ID)
                .build()
            val request = GetCredentialRequest.Builder().addCredentialOption(option).build()
            val result = CredentialManager.create(activity).getCredential(activity, request)
            val cred = result.credential
            if (cred is CustomCredential && cred.type == GoogleIdTokenCredential.TYPE_GOOGLE_ID_TOKEN_CREDENTIAL) {
                val idToken = GoogleIdTokenCredential.createFrom(cred.data).idToken
                auth.signInWithCredential(GoogleAuthProvider.getCredential(idToken, null)).await()
                recordTerms()
            } else {
                _error.value = "That sign-in did not return a Google account."
            }
        } catch (e: GetCredentialCancellationException) {
            // The person closed the picker.
        } catch (e: Exception) {
            Log.w(TAG, "sign-in failed", e)
            _error.value = e.message ?: "Sign-in failed."
        } finally {
            _busy.value = false
        }
    }

    /** Runs before the Firebase user goes away, while a token can still be minted. */
    var beforeSignOut: (suspend () -> Unit)? = null
    /** Runs once the account is deleted, to clear what this phone kept of it. */
    var afterDelete: (suspend () -> Unit)? = null
    private val scope = kotlinx.coroutines.CoroutineScope(kotlinx.coroutines.SupervisorJob() + kotlinx.coroutines.Dispatchers.Main)

    fun signOut() {
        val a = auth ?: return
        scope.launch {
            runCatching { beforeSignOut?.invoke() }
            a.signOut()
        }
    }

    fun clearError() { _error.value = null }

    /** The website's "Delete account": the server removes watches, keys and the user record. */
    suspend fun deleteAccount(): Boolean {
        val u: FirebaseUser = _user.value ?: return false
        val token = token() ?: return false
        _busy.value = true
        return try {
            val (status, _) = Backend.send("DELETE", "/api/watch/account", token)
            if (status !in 200..299) throw BackendError("HTTP $status")
            u.delete().await()
            runCatching { afterDelete?.invoke() }
            true
        } catch (e: Exception) {
            _error.value = "Could not delete the account: ${e.message}"
            false
        } finally {
            _busy.value = false
        }
    }
}

/** Signed-in requests to commutescout.com. */
suspend fun Backend.send(method: String, path: String, token: String, body: String? = null): Pair<Int, String> =
    withContext(Dispatchers.IO) {
        val b = Request.Builder().url("$BASE$path").header("Authorization", "Bearer $token").header("Accept", "application/json")
        when (method) {
            "POST" -> b.post((body ?: "{}").toRequestBody("application/json".toMediaType()))
            "PATCH" -> b.patch((body ?: "{}").toRequestBody("application/json".toMediaType()))
            "DELETE" -> b.delete(body?.toRequestBody("application/json".toMediaType()))
            else -> b.get()
        }
        http.newCall(b.build()).execute().use { r -> r.code to r.body.string() }
    }
