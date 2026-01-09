#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include "SystemMonitor.h"

int main(int argc, char *argv[])
{
    qputenv("QT_SCALE_FACTOR", "2.2");
    QGuiApplication app(argc, argv);

    // 注册 C++ 类型到 QML
    qmlRegisterType<SystemMonitor>("MyDesktop.Backend", 1, 0, "SystemMonitor");

    QQmlApplicationEngine engine;
    const QUrl url(u"qrc:/MyDesktop/Backend/qml/Main.qml"_qs);

    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
                     &app, [url](QObject *obj, const QUrl &objUrl) {
                         if (!obj && url == objUrl)
                             QCoreApplication::exit(-1);
                     }, Qt::QueuedConnection);

    engine.load(url);

    return app.exec();
}
