use std::ffi::{CStr, CString};
use std::io::{BufRead, BufReader};
use std::os::raw::{c_char, c_int, c_void};
use std::panic::AssertUnwindSafe;
use std::sync::LazyLock;
use std::time::Duration;

use serde_json::{json, Value};

type StreamFn = extern "C" fn(*const c_char, c_int, c_int, *mut c_void);

static HTTP: LazyLock<reqwest::blocking::Client> = LazyLock::new(|| {
    reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(90))
        .connect_timeout(Duration::from_secs(15))
        .user_agent("DynamicIsland/1.0")
        .build()
        .expect("cliente http")
});

const SYSTEM_PROMPT: &str = "Eres un asistente dentro de una isla dinámica pequeña en la Mac. \
Responde en el mismo idioma del texto seleccionado. Si es una pregunta, respóndela. \
Si es un fragmento, explica lo esencial. Sé claro y breve. \
Usa Markdown: **negritas** para lo importante, listas con guion cuando haya varios puntos, \
y bloques de código con cercas de tres comillas invertidas cuando haya código. \
Evita títulos salvo que organicen de verdad la respuesta.";

#[no_mangle]
pub extern "C" fn island_engine_version() -> *const c_char {
    static VERSION: &[u8] = b"dynamic-island-core 0.1.0\0";
    VERSION.as_ptr() as *const c_char
}

#[no_mangle]
pub extern "C" fn island_free_string(value: *mut c_char) {
    if value.is_null() {
        return;
    }
    unsafe {
        drop(CString::from_raw(value));
    }
}

#[no_mangle]
pub extern "C" fn island_list_models(provider: *const c_char, api_key: *const c_char) -> *mut c_char {
    let result = std::panic::catch_unwind(AssertUnwindSafe(|| {
        let provider = c_str(provider).unwrap_or_default();
        let api_key = c_str(api_key).unwrap_or_default();
        match list_models(&provider, &api_key) {
            Ok(models) => json!({ "ok": true, "models": models }).to_string(),
            Err(error) => json!({ "ok": false, "error": error }).to_string(),
        }
    }));
    let body = result.unwrap_or_else(|_| {
        json!({ "ok": false, "error": "Fallo interno al listar modelos." }).to_string()
    });
    CString::new(body).unwrap_or_else(|_| CString::new("{\"ok\":false}").unwrap()).into_raw()
}

#[no_mangle]
pub extern "C" fn island_ask(
    provider: *const c_char,
    api_key: *const c_char,
    model: *const c_char,
    text: *const c_char,
    callback: StreamFn,
    ctx: *mut c_void,
) {
    let outcome = std::panic::catch_unwind(AssertUnwindSafe(|| {
        let provider = c_str(provider).unwrap_or_default();
        let api_key = c_str(api_key).unwrap_or_default();
        let model = c_str(model).unwrap_or_default();
        let text = c_str(text).unwrap_or_default();
        ask(&provider, &api_key, &model, &text, callback, ctx)
    }));
    match outcome {
        Ok(Ok(())) => {}
        Ok(Err(error)) => emit(callback, ctx, &error, true, true),
        Err(_) => emit(callback, ctx, "Fallo interno del motor.", true, true),
    }
}

fn c_str(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(ptr).to_str().ok().map(|s| s.to_string()) }
}

fn emit(callback: StreamFn, ctx: *mut c_void, text: &str, is_error: bool, is_done: bool) {
    let cleaned = text.replace('\0', "");
    let c = CString::new(cleaned).unwrap_or_else(|_| CString::new("").unwrap());
    callback(
        c.as_ptr(),
        if is_error { 1 } else { 0 },
        if is_done { 1 } else { 0 },
        ctx,
    );
}

fn list_models(provider: &str, api_key: &str) -> Result<Vec<Value>, String> {
    let api_key = api_key.trim();
    if api_key.is_empty() {
        return Err("Escribe una API key.".into());
    }
    let models = match provider {
        "gemini" => list_gemini(api_key)?,
        "openai" => list_openai(api_key)?,
        _ => return Err("Proveedor desconocido.".into()),
    };
    if models.is_empty() {
        return Err("Esa clave no devolvió modelos.".into());
    }
    Ok(models
        .into_iter()
        .map(|model| json!({ "id": model.id, "label": model.label }))
        .collect())
}

struct ListedModel {
    id: String,
    label: String,
    created: i64,
}

fn list_openai(api_key: &str) -> Result<Vec<ListedModel>, String> {
    let mut models = Vec::new();
    let mut cursor: Option<String> = None;
    for _ in 0..40 {
        let mut url = "https://api.openai.com/v1/models".to_string();
        if let Some(cursor) = &cursor {
            url.push_str("?after=");
            url.push_str(&url_encode(cursor));
        }
        let response = HTTP
            .get(&url)
            .bearer_auth(api_key)
            .send()
            .map_err(|error| humanize(&error.to_string()))?;
        let status = response.status();
        let body = response.text().map_err(|error| humanize(&error.to_string()))?;
        if !status.is_success() {
            if models.is_empty() {
                return Err(http_error(status.as_u16(), &body));
            }
            break;
        }
        let value: Value = serde_json::from_str(&body).map_err(|_| "OpenAI devolvió un listado ilegible.".to_string())?;
        let page = parse_openai_models(&value);
        if page.is_empty() {
            break;
        }
        let page_last = value
            .get("data")
            .and_then(|item| item.as_array())
            .and_then(|items| items.last())
            .and_then(|item| item.get("id"))
            .and_then(|item| item.as_str())
            .map(str::to_string);
        models.extend(page);
        let has_more = value.get("has_more").and_then(|item| item.as_bool()).unwrap_or(false);
        match (has_more, page_last) {
            (true, Some(next)) if cursor.as_deref() != Some(next.as_str()) => cursor = Some(next),
            _ => break,
        }
    }
    models.sort_by(|a, b| b.created.cmp(&a.created).then_with(|| a.id.cmp(&b.id)));
    models.dedup_by(|a, b| a.id == b.id);
    Ok(models)
}

fn list_gemini(api_key: &str) -> Result<Vec<ListedModel>, String> {
    let mut models = Vec::new();
    let mut page_token = String::new();
    for _ in 0..8 {
        let mut url = "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000".to_string();
        if !page_token.is_empty() {
            url.push_str("&pageToken=");
            url.push_str(&url_encode(&page_token));
        }
        let response = HTTP
            .get(&url)
            .header("x-goog-api-key", api_key)
            .send()
            .map_err(|error| humanize(&error.to_string()))?;
        let status = response.status();
        let body = response.text().map_err(|error| humanize(&error.to_string()))?;
        if !status.is_success() {
            return Err(http_error(status.as_u16(), &body));
        }
        let value: Value = serde_json::from_str(&body).map_err(|_| "Gemini devolvió un listado ilegible.".to_string())?;
        models.extend(parse_gemini_models(&value));
        match value.get("nextPageToken").and_then(|token| token.as_str()) {
            Some(token) if !token.is_empty() => page_token = token.to_string(),
            _ => break,
        }
    }
    models.sort_by(|a, b| b.id.to_lowercase().cmp(&a.id.to_lowercase()));
    models.dedup_by(|a, b| a.id == b.id);
    Ok(models)
}

fn parse_openai_models(value: &Value) -> Vec<ListedModel> {
    let Some(data) = value.get("data").and_then(|item| item.as_array()) else {
        return Vec::new();
    };
    data.iter()
        .filter_map(|item| {
            let id = item.get("id")?.as_str()?.trim();
            if id.is_empty() {
                return None;
            }
            let created = item.get("created").and_then(|v| v.as_i64()).unwrap_or(0);
            Some(ListedModel {
                id: id.to_string(),
                label: pretty_model_label(id),
                created,
            })
        })
        .collect()
}

fn pretty_model_label(id: &str) -> String {
    id.split('-')
        .filter(|part| !part.is_empty())
        .map(|part| {
            let lower = part.to_ascii_lowercase();
            if lower == "gpt" {
                return "GPT".to_string();
            }
            let mut chars = part.chars();
            match chars.next() {
                Some(first) => first.to_uppercase().collect::<String>() + chars.as_str(),
                None => String::new(),
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

fn parse_gemini_models(value: &Value) -> Vec<ListedModel> {
    let Some(models) = value.get("models").and_then(|item| item.as_array()) else {
        return Vec::new();
    };
    models
        .iter()
        .filter_map(|item| {
            let name = item.get("name").and_then(|v| v.as_str()).unwrap_or("").trim();
            if name.is_empty() {
                return None;
            }
            let id = name
                .strip_prefix("models/")
                .unwrap_or(name)
                .to_string();
            let label = item
                .get("displayName")
                .and_then(|v| v.as_str())
                .filter(|label| !label.trim().is_empty())
                .unwrap_or(&id)
                .to_string();
            Some(ListedModel { id, label, created: 0 })
        })
        .collect()
}

fn ask(
    provider: &str,
    api_key: &str,
    model: &str,
    text: &str,
    callback: StreamFn,
    ctx: *mut c_void,
) -> Result<(), String> {
    let api_key = api_key.trim();
    let model = model.trim();
    let text = text.trim();
    if api_key.is_empty() {
        return Err("Escribe una API key.".into());
    }
    if model.is_empty() {
        return Err("Elige un modelo.".into());
    }
    if text.is_empty() {
        return Err("No hay texto seleccionado.".into());
    }
    let clipped: String = text.chars().take(12_000).collect();
    let result = match provider {
        "gemini" => ask_gemini(api_key, model, &clipped, callback, ctx),
        "openai" => ask_openai(api_key, model, &clipped, callback, ctx),
        _ => Err("Proveedor desconocido.".into()),
    };
    match result {
        Ok(()) => emit(callback, ctx, "", false, true),
        Err(error) => emit(callback, ctx, &error, true, true),
    }
    Ok(())
}

fn ask_openai(api_key: &str, model: &str, text: &str, callback: StreamFn, ctx: *mut c_void) -> Result<(), String> {
    let messages = if prefers_single_user_message(model) {
        json!([
            { "role": "user", "content": format!("{SYSTEM_PROMPT}\n\nTexto seleccionado:\n{text}") }
        ])
    } else {
        json!([
            { "role": "system", "content": SYSTEM_PROMPT },
            { "role": "user", "content": text }
        ])
    };
    let mut body = json!({
        "model": model,
        "stream": true,
        "messages": messages
    });
    let id = model.to_ascii_lowercase();
    if id.contains("gpt-5") || id.contains("gpt-6") || id.starts_with('o') {
        body["reasoning_effort"] = json!("low");
    }
    let response = HTTP
        .post("https://api.openai.com/v1/chat/completions")
        .bearer_auth(api_key)
        .json(&body)
        .send()
        .map_err(|error| humanize(&error.to_string()))?;
    consume_response(response, callback, ctx)
}

fn ask_gemini(api_key: &str, model: &str, text: &str, callback: StreamFn, ctx: *mut c_void) -> Result<(), String> {
    let resource = if model.starts_with("models/") || model.starts_with("tunedModels/") {
        model.to_string()
    } else {
        format!("models/{model}")
    };
    let url = format!("https://generativelanguage.googleapis.com/v1beta/{resource}:streamGenerateContent?alt=sse");
    let response = HTTP
        .post(url)
        .header("x-goog-api-key", api_key)
        .json(&json!({
            "systemInstruction": { "parts": [{ "text": SYSTEM_PROMPT }] },
            "contents": [{ "role": "user", "parts": [{ "text": text }] }]
        }))
        .send()
        .map_err(|error| humanize(&error.to_string()))?;
    consume_response(response, callback, ctx)
}

fn prefers_single_user_message(model: &str) -> bool {
    let model = model.to_ascii_lowercase();
    model.starts_with("o1") || model.starts_with("o3") || model.starts_with("o4")
}

fn consume_response(response: reqwest::blocking::Response, callback: StreamFn, ctx: *mut c_void) -> Result<(), String> {
    let status = response.status();
    let content_type = response
        .headers()
        .get(reqwest::header::CONTENT_TYPE)
        .and_then(|value| value.to_str().ok())
        .unwrap_or("")
        .to_ascii_lowercase();
    if !status.is_success() {
        let body = response.text().unwrap_or_default();
        return Err(http_error(status.as_u16(), &body));
    }
    if content_type.contains("application/json") && !content_type.contains("text/event-stream") {
        let body = response.text().map_err(|error| humanize(&error.to_string()))?;
        return emit_json_body(&body, callback, ctx);
    }
    let mut reader = BufReader::new(response);
    let mut line = String::new();
    let mut emitted = 0usize;
    loop {
        line.clear();
        let read = reader.read_line(&mut line).map_err(|error| humanize(&error.to_string()))?;
        if read == 0 {
            break;
        }
        match parse_stream_line(&line) {
            StreamEvent::Text(text) => {
                emitted += text.chars().count();
                emit(callback, ctx, &text, false, false);
                if emitted > 8_000 {
                    break;
                }
            }
            StreamEvent::Done => break,
            StreamEvent::Error(error) => return Err(error),
            StreamEvent::Ignore => {}
        }
    }
    if emitted == 0 {
        return Err("El modelo no devolvió texto.".into());
    }
    Ok(())
}

fn emit_json_body(body: &str, callback: StreamFn, ctx: *mut c_void) -> Result<(), String> {
    let value: Value = serde_json::from_str(body).map_err(|_| "La respuesta no es JSON.".to_string())?;
    let mut emitted = 0usize;
    let values: Vec<&Value> = if let Some(array) = value.as_array() {
        array.iter().collect()
    } else {
        vec![&value]
    };
    for item in values {
        match event_from_value(item) {
            StreamEvent::Text(text) => {
                emitted += text.chars().count();
                emit(callback, ctx, &text, false, false);
            }
            StreamEvent::Error(error) => return Err(error),
            StreamEvent::Done | StreamEvent::Ignore => {}
        }
    }
    if emitted == 0 {
        return Err("El modelo no devolvió texto.".into());
    }
    Ok(())
}

enum StreamEvent {
    Text(String),
    Done,
    Error(String),
    Ignore,
}

fn parse_stream_line(line: &str) -> StreamEvent {
    let line = line.trim();
    if line.is_empty() || line.starts_with(':') {
        return StreamEvent::Ignore;
    }
    let payload = line.strip_prefix("data:").map(str::trim).unwrap_or(line);
    if payload == "[DONE]" {
        return StreamEvent::Done;
    }
    if !payload.starts_with('{') && !payload.starts_with('[') {
        return StreamEvent::Ignore;
    }
    let value: Value = match serde_json::from_str(payload) {
        Ok(value) => value,
        Err(_) => return StreamEvent::Ignore,
    };
    if let Some(array) = value.as_array() {
        let mut combined = String::new();
        for item in array {
            match event_from_value(item) {
                StreamEvent::Text(text) => combined.push_str(&text),
                StreamEvent::Error(error) => return StreamEvent::Error(error),
                StreamEvent::Done => return StreamEvent::Done,
                StreamEvent::Ignore => {}
            }
        }
        return if combined.is_empty() {
            StreamEvent::Ignore
        } else {
            StreamEvent::Text(combined)
        };
    }
    event_from_value(&value)
}

fn event_from_value(value: &Value) -> StreamEvent {
    if let Some(message) = value.pointer("/error/message").and_then(|item| item.as_str()) {
        return StreamEvent::Error(message.chars().take(280).collect());
    }
    if let Some(reason) = value.pointer("/promptFeedback/blockReason").and_then(|item| item.as_str()) {
        return StreamEvent::Error(format!("Gemini bloqueó la solicitud ({reason})."));
    }
    if let Some(text) = value.pointer("/choices/0/delta/content").and_then(|item| item.as_str()) {
        return text_event(text);
    }
    if let Some(text) = value.pointer("/choices/0/message/content").and_then(|item| item.as_str()) {
        return text_event(text);
    }
    if let Some(parts) = value.pointer("/candidates/0/content/parts").and_then(|item| item.as_array()) {
        let mut combined = String::new();
        for part in parts {
            if part.get("thought").and_then(|item| item.as_bool()) == Some(true) {
                continue;
            }
            if let Some(text) = part.get("text").and_then(|item| item.as_str()) {
                combined.push_str(text);
            }
        }
        return text_event(&combined);
    }
    StreamEvent::Ignore
}

fn text_event(text: &str) -> StreamEvent {
    if text.is_empty() {
        StreamEvent::Ignore
    } else {
        StreamEvent::Text(text.to_string())
    }
}

fn http_error(status: u16, body: &str) -> String {
    let detail = serde_json::from_str::<Value>(body)
        .ok()
        .and_then(|value| value.pointer("/error/message").and_then(|item| item.as_str()).map(|s| s.to_string()))
        .unwrap_or_else(|| body.trim().chars().take(180).collect());
    let headline = match status {
        401 | 403 => "La API key fue rechazada.",
        404 => "Ese modelo no está disponible.",
        429 => "Límite de uso alcanzado. Espera un momento.",
        _ => "La solicitud falló.",
    };
    if detail.is_empty() {
        headline.to_string()
    } else {
        format!("{headline} {detail}")
    }
}

fn humanize(error: &str) -> String {
    let lower = error.to_ascii_lowercase();
    if lower.contains("timed out") || lower.contains("timeout") {
        return "La solicitud tardó demasiado.".into();
    }
    if lower.contains("dns") || lower.contains("connect") || lower.contains("network") {
        return "No hay conexión con el servicio.".into();
    }
    format!("Error de red: {}", error.chars().take(180).collect::<String>())
}

fn url_encode(value: &str) -> String {
    let mut out = String::new();
    for byte in value.bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => out.push(byte as char),
            _ => out.push_str(&format!("%{byte:02X}")),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_openai_stream_chunk() {
        let line = "data: {\"choices\":[{\"delta\":{\"content\":\"Hola\"}}]}";
        match parse_stream_line(line) {
            StreamEvent::Text(text) => assert_eq!(text, "Hola"),
            _ => panic!("esperaba texto"),
        }
    }

    #[test]
    fn parses_done_marker() {
        assert!(matches!(parse_stream_line("data: [DONE]"), StreamEvent::Done));
    }

    #[test]
    fn parses_gemini_part_and_skips_thoughts() {
        let line = "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"pienso\",\"thought\":true},{\"text\":\"Respuesta\"}]}}]}";
        match parse_stream_line(line) {
            StreamEvent::Text(text) => assert_eq!(text, "Respuesta"),
            _ => panic!("esperaba la respuesta"),
        }
    }

    #[test]
    fn keeps_every_openai_model() {
        let value = json!({
            "data": [
                {"id": "gpt-6-luna", "created": 30},
                {"id": "gpt-4o", "created": 10},
                {"id": "text-embedding-3-large", "created": 12},
                {"id": "whisper-1", "created": 9},
                {"id": "o3", "created": 20}
            ]
        });
        let models = parse_openai_models(&value);
        let luna = models.iter().find(|model| model.id == "gpt-6-luna").unwrap();
        assert_eq!(luna.label, "GPT 6 Luna");
        assert_eq!(models.len(), 5);
    }

    #[test]
    fn keeps_every_gemini_model() {
        let value = json!({
            "models": [
                {
                    "name": "models/gemini-2.5-flash",
                    "displayName": "Gemini 2.5 Flash",
                    "supportedGenerationMethods": ["generateContent", "countTokens"]
                },
                {
                    "name": "models/text-embedding-004",
                    "displayName": "Embedding",
                    "supportedGenerationMethods": ["embedContent"]
                },
                {
                    "name": "models/gemini-embedding-001",
                    "displayName": "Embed",
                    "supportedActions": ["embedContent"]
                }
            ]
        });
        let models = parse_gemini_models(&value);
        assert_eq!(models.len(), 3);
        assert!(models.iter().any(|model| model.id == "gemini-2.5-flash" && model.label == "Gemini 2.5 Flash"));
        assert!(models.iter().any(|model| model.id == "text-embedding-004"));
    }
}
