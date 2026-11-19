package com.commutescout.drive

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.commutescout.drive.design.DG
import com.commutescout.drive.design.tag

/**
 * The Terms of Use and Privacy Policy a person agrees to when signing in.
 *
 * Signing in with Google creates the account on first use, and the app
 * cannot tell a new account from a returning one until after it exists,
 * so the agreement is asked per phone: the first sign-in here opens a
 * dialog with an unticked "I agree" box, and its sign-in button stays
 * disabled until the box is ticked. Once this phone agreed to the
 * current version, later sign-ins go straight through, and the sign-in
 * spots show the passive line. The account records the acceptance with
 * POST /api/me/terms right after sign-in. Bump [VERSION] with the
 * server's TERMS_VERSION; a new version asks again.
 */
object TermsConsent {
    const val VERSION = "2026-11-19"
    const val PREF_KEY = "terms.accepted"
    const val TERMS_URL = "https://commutescout.com/terms"
    const val PRIVACY_URL = "https://commutescout.com/privacy"
    const val PASSIVE = "By continuing you agree to the Terms of Use and Privacy Policy."

    /** Whether this phone already agreed to the current version. */
    fun agreed(stored: String?) = stored == VERSION

    /** The sign-in button works once agreed here before, or ticked now. */
    fun canSignIn(stored: String?, ticked: Boolean) = agreed(stored) || ticked

    /** The account endpoint's body. */
    fun body() = """{"version":"$VERSION"}"""
}

/** "I agree to the Terms of Use and Privacy Policy", or the passive line, with both documents linked. */
fun termsText(passive: Boolean): AnnotatedString = buildAnnotatedString {
    val link = TextLinkStyles(SpanStyle(color = DG.low, textDecoration = TextDecoration.Underline))
    append(if (passive) "By continuing you agree to the " else "I agree to the ")
    withLink(LinkAnnotation.Url(TermsConsent.TERMS_URL, link)) { append("Terms of Use") }
    append(" and ")
    withLink(LinkAnnotation.Url(TermsConsent.PRIVACY_URL, link)) { append("Privacy Policy") }
    if (passive) append(".")
}

/**
 * Shown while [Account.signInWithGoogle] waits for the agreement: an
 * unticked box, and "Continue with Google" disabled until it is ticked.
 * Hosted once at the root, so every sign-in button in the app goes
 * through it.
 */
@Composable
fun TermsConsentDialog(account: Account) {
    val asking by account.consentAsk.collectAsStateWithLifecycle()
    if (!asking) return
    var ticked by remember { mutableStateOf(false) }
    AlertDialog(
        onDismissRequest = { account.answerConsent(false) },
        modifier = Modifier.tag("terms-dialog"),
        title = { Text("Before you sign in") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("Signing in creates your CommuteScout account the first time, the same account as commutescout.com.")
                Row(Modifier.clickable(role = Role.Checkbox) { ticked = !ticked }.tag("terms-agree"),
                    verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(ticked, { ticked = it })
                    Text(termsText(passive = false), Modifier.padding(start = 4.dp))
                }
            }
        },
        confirmButton = {
            TextButton({ account.answerConsent(true) }, Modifier.tag("terms-continue"), enabled = ticked) { Text("Continue with Google") }
        },
        dismissButton = { TextButton({ account.answerConsent(false) }) { Text("Cancel") } },
    )
}
