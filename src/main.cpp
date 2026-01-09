#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include "SystemMonitor.h"

int main(int argc, char *argv[])
{
    qputenv("QT_SCALE_FACTOR", "2.2");
    QGuiApplication app(argc, argv);

    // 注册 C++ 类型到 QML
    qmlRegisterType<SystemMonitor>("MyDesktop.Backend", 1, 0, "SystemMonitor");

    QQmlApplicationEngine engine;

#ifdef GIT_COMMIT_HASH
    QString buildHash = QStringLiteral(GIT_COMMIT_HASH);
#else
    QString buildHash = QStringLiteral("Unknown");
#endif
    
    // 设置为全局上下文属性，QML中可以直接使用 "appBuildHash" 变量
    engine.rootContext()->setContextProperty("appBuildHash", buildHash);
    engine.rootContext()->setContextProperty("appName", "Orbital");

    const QUrl url(u"qrc:/MyDesktop/Backend/qml/Main.qml"_qs);
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
                     &app, [url](QObject *obj, const QUrl &objUrl) {
        if (!obj && url == objUrl)
            QCoreApplication::exit(-1);
    }, Qt::QueuedConnection);
    
    engine.load(url);

    return app.exec();
}
