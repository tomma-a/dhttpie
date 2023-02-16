import std.stdio, std.json;
import std.json, std.exception, std.file;
import std.conv, std.typecons;
import requests;
import core.time;
import std.getopt, std.string;

enum HttpMethod
{
    GET,
    POST,
    PUT,
    DELETE
}

enum ParamType
{
    Query,
    Header,
    Data,
    RJson,
    FileData,
    Unknown
}

immutable dhttp_version = "dhttp version : 0.1";
const string helpText = q"{
dhttp is simple version of famous http(python) alernative
}";
int main(string[] args)
{
    HttpMethod method = HttpMethod.GET;
    int urlpos = 2;
    int durseconds = -1;
    int maxdirect = -1;
    bool verbose = false;
    bool json = false;
    bool formpost = false;
    bool showversion = false;
    string outfilename="";
    string userpass = "";
    File outfile=stdout;
    auto argsp = getopt(args, std.getopt.config.caseSensitive, "V|verbose", "verbose mode",
            &verbose, "f|form", "form post", &formpost, "j|json",
            "json format", &json, "u|auth", "basic user auth", &userpass,
            "-t|timeout", "timeout seconds", &durseconds, "max-redirects",
            "max direct ", &maxdirect,"o|out","output content to the file",&outfilename, "v|version", "show version", &showversion);
    if (argsp.helpWanted)
    {
        defaultGetoptPrinter(helpText, argsp.options);
        return 0;
    }
    if (showversion)
    {
        defaultGetoptPrinter(dhttp_version, argsp.options);
        return 0;
    }
    if (userpass.length > 0)
    {
        enforce(userpass.indexOf(":") > 0, "basic auth user:pass format");
    }
    if (args.length < 2)
    {
        writeln("http [method] url ...");
        return 0;
    }
    if (isHttpMethod(args[1]))
    {
        method = to!(HttpMethod)(args[1].toUpper());
    }
    else
    {
        urlpos = 1;
    }

    auto req = Request();
    if (verbose)
        req.verbosity = 2;
    if (durseconds >= 0)
        req.timeout = dur!"seconds"(durseconds);
    if (maxdirect >= 0)
        req.maxRedirects = maxdirect;
    if(outfilename.length>0)
	outfile=File(outfilename,"wb");
    if (userpass.length > 0)
    {
        auto ss = userpass.split(":");
        req.authenticator = new BasicAuthentication(ss[0], ss[1 .. $].join(":"));
    }
    QueryParam[] params;
    JSONValue jsons;
    MultipartForm forms;
    for (int i = urlpos + 1; i < args.length; i++)
    {
        auto argtype = parseParam(args[i]);
        switch (argtype[0])
        {
        case ParamType.Query:
            params ~= QueryParam(argtype[1], argtype[2]);
            break;
        case ParamType.Header:
            string[string] htmp;
            htmp[argtype[1]] = argtype[2];
            req.addHeaders(htmp);
            break;
        case ParamType.Data:
            if (formpost)
            {
                forms.add(formData(argtype[1], argtype[2]));
            }
            else if (json)
            {
                jsons[argtype[1]] = argtype[2];
            }
            else
            {
                params ~= QueryParam(argtype[1], argtype[2]);
            }
            break;
        case ParamType.RJson:
            jsons[argtype[1]] = parseJSON(argtype[2]);
            break;
        case ParamType.FileData:
            forms.add(formData("file", File(argtype[1],
                    "rb"), [
                    "filename": argtype[1],
                    "Content-Type": "text/plain"
            ]));
            break;
        default:

        }
    }
    switch (method)
    {
    case HttpMethod.GET:
        auto resp = req.get(args[urlpos], params);
        outfile.writeln(resp.responseBody);
        break;
    case HttpMethod.POST:
        if (formpost)
        {
            auto resp = req.post(args[urlpos], forms);
            outfile.writeln(resp.responseBody);
        }
        else if (json)
        {
            auto resp = req.post(args[urlpos], to!(string)(jsons), "application/json");
            outfile.writeln(resp.responseBody);
        }
        else
        {
            auto resp = req.post(args[urlpos], params);
            outfile.writeln(resp.responseBody);
        }
        break;
    case HttpMethod.PUT:
        auto resp = req.put(args[urlpos], queryParams());
        outfile.writeln(resp.responseBody);
        break;
    default:
        auto resp = req.deleteRequest(args[urlpos], queryParams());
        outfile.writeln(resp.responseBody);
    }
    if(outfilename.length>0)
	outfile.close();
    return 0;
}

bool isHttpMethod(string m)
{
    auto mu = m.toUpper();
    if (m == "GET" || m == "POST" || m == "PUT" || m == "DELETE")
        return true;
    return false;
}

auto parseParam(string v)
{
    auto iquery = v.indexOf("==");
    auto iheader = v.indexOf(":");
    auto idata = v.indexOf("=");
    auto irjson = v.indexOf(":=");
    if (v.startsWith("@") && isFile(v[1 .. $]))
    {
        return tuple(ParamType.FileData, v[1 .. $], "");
    }
    else if (iquery > 0)
    {
        auto ss = v.split("==");
        return tuple(ParamType.Query, ss[0], ss[1 .. $].join("=="));
    }
    else if (irjson > 0)
    {
        auto ss = v.split(":=");
        return tuple(ParamType.RJson, ss[0], ss[1 .. $].join(":="));
    }
    else if (idata > 0)
    {
        auto ss = v.split("=");
        return tuple(ParamType.Data, ss[0], ss[1 .. $].join("="));
    }
    else if (iheader > 0)
    {
        auto ss = v.split(":");
        return tuple(ParamType.Header, ss[0], ss[1 .. $].join(":"));
    }
    else
    {
        return tuple(ParamType.Unknown, "", "");
    }

}
