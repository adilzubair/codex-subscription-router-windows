package control

import (
	"embed"
	"net/http"
	"strings"
)

//go:embed manager/*
var managerFiles embed.FS

func (s *Server) manager(response http.ResponseWriter, request *http.Request) {
	if request.URL.Path != "/" && request.URL.Path != "/manager" {
		http.NotFound(response, request)
		return
	}
	if request.Method != http.MethodGet {
		methodNotAllowed(response)
		return
	}
	if request.URL.Path == "/" {
		http.Redirect(response, request, "/manager"+fragmentPreservingQuery(request), http.StatusTemporaryRedirect)
		return
	}
	serveManagerFile(response, "manager/index.html", "text/html; charset=utf-8")
}

func (s *Server) managerAsset(response http.ResponseWriter, request *http.Request) {
	if request.Method != http.MethodGet {
		methodNotAllowed(response)
		return
	}
	name := strings.TrimPrefix(request.URL.Path, "/manager/assets/")
	switch name {
	case "manager.css":
		serveManagerFile(response, "manager/manager.css", "text/css; charset=utf-8")
	case "manager.js":
		serveManagerFile(response, "manager/manager.js", "text/javascript; charset=utf-8")
	default:
		http.NotFound(response, request)
	}
}

func serveManagerFile(response http.ResponseWriter, name, contentType string) {
	contents, err := managerFiles.ReadFile(name)
	if err != nil {
		http.Error(response, "manager asset unavailable", http.StatusInternalServerError)
		return
	}
	response.Header().Set("Content-Type", contentType)
	response.Header().Set(
		"Content-Security-Policy",
		"default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src https: data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
	)
	response.WriteHeader(http.StatusOK)
	_, _ = response.Write(contents)
}

func fragmentPreservingQuery(request *http.Request) string {
	if request.URL.RawQuery == "" {
		return ""
	}
	return "?" + request.URL.RawQuery
}
